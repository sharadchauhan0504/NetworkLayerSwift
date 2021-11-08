import UIKit


/*
 
 This network layers works with Routable protocol.
 APIRouter class is a generic class, which is responsible for making api calls and decoding response. This takes Codable type and returns the expected result model or error.
 API service class implements Routable protocol. Here we can add cases based on our apis, it is highly scalable and provides all required params for an API request.
 View model can then create and object of APIService and pass Codable and session object to APIRouter object.
 
 */

//MARK:- Error response codable
struct APIErrorResponse: Codable {
    let message: String
}

//MARK:- Generic errors in App
enum GenericErrors: Error {
    
    case invalidAPIResponse
    case decodingError
    
    var message: String {
        switch self {
        case .invalidAPIResponse: return "The page you’re requesting appears to be stuck in traffic. Refresh to retrieve!"
        case .decodingError: return "Our servers started speaking a language we are yet to learn. Bear with us."
        }
    }
    
}

//MARK:- HTTP methods
enum HTTPMethod: String {
    case GET
    case POST
    case PUT
    case DELETE
    case PATCH
}

//MARK:- API call class
struct APIRouter<T: Codable> {
    
    // MARK: - Local Variables
    private let session: URLSession!
    
    // MARK: - Init
    init(session: URLSession) {
        self.session = session
    }
    
    // MARK: API Request
    func requestData(_ router: Routable,
                     completion : @escaping (_ model : T?, _ statusCode: Int? , _ error : Error?) -> Void ) {
        
        let queue = DispatchQueue(label: "NetworkThread", qos: .background, attributes: .concurrent, autoreleaseFrequency: .workItem, target: .none)
        queue.async {
            let task = self.session.dataTask(with: router.request) { (data, response, error) in
                //Logging
                if let properData = router.request.httpBody {
                    do {
                        let output = try JSONSerialization.jsonObject(with: properData, options: .allowFragments)
                        print("Request Body: \(String(describing: output))")
                    } catch {
                        print("httpBody logging error: \(error)")
                    }
                }
                
                if let properData = data {
                    do {
                        let output = try JSONSerialization.jsonObject(with: properData, options: .allowFragments)
                        print("RESPONSE: \(String(describing: output))")
                    } catch {
                    }
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    print("\(httpResponse.statusCode), \(String(describing: httpResponse.url?.absoluteString))")
                    curateResponseForUI(router, data, httpResponse.statusCode, error, completion: completion)
                } else {
                    curateResponseForUI(router, data, nil, error, completion: completion)
                }
            }
            task.resume()
        }
        
        
    }
    
    private func curateResponseForUI(_ router: Routable, _ data: Data?, _ statusCode: Int?, _ error: Error?, completion : @escaping (_ model : T?, _ statusCode: Int? , _ error : Error?) -> Void) {
        guard error == nil, let code = statusCode, (200..<300) ~= code else {
            guard let errorData = data, let code = statusCode else {
                completion(nil, statusCode, GenericErrors.invalidAPIResponse)
                return
            }
            do {
                let errorModel = try JSONDecoder().decode(APIErrorResponse.self, from: errorData)
                let customError = NSError(domain: "healthifyme.co", code: code, userInfo:[ NSLocalizedDescriptionKey: errorModel.message]) as Error
                completion(nil, statusCode, customError)
            } catch {
                completion(nil, statusCode, GenericErrors.invalidAPIResponse)
            }
            return
        }
        
        guard let properData = data else {
            completion(nil, statusCode, GenericErrors.invalidAPIResponse)
            return
        }
        
        do {
            let model = try JSONDecoder().decode(T.self, from: properData)
            completion(model, statusCode,  nil)
        } catch {
            completion(nil, statusCode, GenericErrors.decodingError)
        }
    }
}

//MARK:- Protocol
protocol Routable {
    var url: URL { get }
    var method: HTTPMethod { get }
    var endPoint: String { get }
    var headers: [String: String] { get }
    var body: Data? { get }
    var request: URLRequest { get }
}

//MARK:- API client for base urls
enum APIClient {
    
    case baseUrl
    
    var urlString: String {
        switch self {
        case .baseUrl: return "base_url"
        }
    }
}

//MARK:- API service class
enum ExampleAPIService: Routable {
        
    case getSomeData(_ id: Int)
    
    var url: URL {
        switch self {
        case .getSomeData: return URL(string: APIClient.baseUrl.urlString + endPoint)!
        }
    }
    
    var method: HTTPMethod {
        switch self {
        case .getSomeData: return .GET
        }
    }
    
    var endPoint: String {
        switch self {
        case .getSomeData(let id): return "/employee/details?id=\(id)"
        }
    }
    
    var headers: [String : String] {
        switch self {
        case .getSomeData: return [
            "Content-Type": "application/json",
            "Authorization": "Bearer token"
            ]
        }
    }
    
    var body: Data? {
        switch self {
        case .getSomeData: return nil
        }
    }
    
    var request: URLRequest {
        var request                 = URLRequest(url: self.url)
        request.httpMethod          = self.method.rawValue
        request.allHTTPHeaderFields = self.headers
        request.httpBody            = self.body
        request.cachePolicy         = .reloadRevalidatingCacheData
        return request
    }
    
    
}

//MARK:- Codable for expected response
struct GetSomeOutput: Codable {}

//MARK:- View Model class
class ViewModel {

    // MARK: - Local Variables
    private let session = URLSession(configuration: .ephemeral, delegate: nil, delegateQueue: nil)
    
    //MARK:- Callbacks
    var apiFailureCallback: ((String) -> Void)?
    var getSuccessCallback: (() -> Void)?

    
    //MARK:- Private methods
    private func getFoodQuantity(_ id: Int) {
        let api = ExampleAPIService.getSomeData(id)
        let router = APIRouter<GetSomeOutput>(session: session)
        
        router.requestData(api) { [weak self] (output, statusCode, error) in
            guard let strongSelf = self else {return}
            if let _ = output, let callback = strongSelf.getSuccessCallback {
                callback()
            } else if let callback = strongSelf.apiFailureCallback, let errorMessage = error?.localizedDescription {
                callback(errorMessage)
            } else if let callback = strongSelf.apiFailureCallback {
                callback(GenericErrors.invalidAPIResponse.localizedDescription)
            }
        }
    }
}

//MARK: - Mock URL Sessions
enum GenericErrors: Error {
    
    case invalidAPIResponse
    case decodingError
    
    var message: String {
        switch self {
        case .invalidAPIResponse: return "The page you’re requesting appears to be stuck in traffic. Refresh to retrieve!"
        case .decodingError: return "Our servers started speaking a language we are yet to learn. Bear with us."
        }
    }
    
}

class MockURLSession: URLSessionProtocol {
    
    var testDataTask = MockURLSessionDataTask()
    var testDataJSONFile: String?
    var testError: Error?
    var testMethod: String?
    
    private var testData: Data?
    private (set) var lastURL: URL?
    
    private var defaultTestBundle: Bundle? {
        return Bundle.allBundles.first { $0.bundlePath.hasSuffix(".xctest") }
    }
    
    func successHttpURLResponse(request: URLRequest) -> URLResponse {
        return HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
    }
    
    func failureHttpURLResponse(request: URLRequest) -> URLResponse {
        return HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: "HTTP/1.1", headerFields: nil)!
    }
    
    func dataTask(with request: URLRequest, completionHandler: @escaping ((Data?, URLResponse?, Error?) -> Void)) -> URLSessionDataTaskProtocol {
        lastURL = request.url
        testMethod = request.httpMethod
        do {
            guard let path = defaultTestBundle?.path(forResource: testDataJSONFile, ofType: "json") else {
                testError = GenericErrors.invalidAPIResponse
                completionHandler(testData, failureHttpURLResponse(request: request), testError)
                return testDataTask
            }
            testData = try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
        } catch {}
        completionHandler(testData, successHttpURLResponse(request: request), testError)
        return testDataTask
    }

    
}

class MockURLSessionDataTask: URLSessionDataTaskProtocol {
    private (set) var resumeWasCalled = false
    
    func resume() {
        resumeWasCalled = true
    }
}

protocol URLSessionProtocol {
    typealias DataTaskResult = (Data?, URLResponse?, Error?) -> Void
    
    func dataTask(with request: URLRequest, completionHandler: @escaping DataTaskResult) -> URLSessionDataTaskProtocol
}

extension URLSession: URLSessionProtocol {
    func dataTask(with request: URLRequest, completionHandler: @escaping URLSessionProtocol.DataTaskResult) -> URLSessionDataTaskProtocol {
        return dataTask(with: request, completionHandler: completionHandler) as URLSessionDataTask
    }
}

extension URLSessionDataTask: URLSessionDataTaskProtocol {}

protocol URLSessionDataTaskProtocol {
    func resume()
}
