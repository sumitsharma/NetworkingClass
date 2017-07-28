//
//  FMConnectionManager.swift
//  Flirt Me
//
//  Created by Vishwajeet Kumar on 5/15/17.
//  Copyright © 2017 Vishwajeet Kumar. All rights reserved.
//

import UIKit

public enum Method: String {
    case POST = "POST"
    case GET = "GET"
    case PUT = "PUT"
    case DELETE = "DELETE"
}

public enum ResponseStatus:Int {
    case tokenExpired = -3
    case networkNotAvailable
    case unknownError
    case failed
    case success
}

public enum ImageType:Int {
    case png
    case jpeg
}

fileprivate enum ResponseCode:Int {
    case success = 200
    case tokenExpired = 4000
}

typealias responseHandler = (_ response: [String: Any]?, _ status: ResponseStatus, _ error: Error?) -> Void

public class FMConnectionManager: NSObject {
    
    static let shared = FMConnectionManager()
    
    func sendRequest(_ method: Method = .POST, _ urlString: String, _ parameters: [String: Any]? = nil, _ authentication: Bool = false, _ onCompletion: @escaping responseHandler) {
        
        if isInternetReachable() {
            _jsonRequest(urlString, parameters)
            guard let url = URL(string: urlString) else {
                return
            }
            let request = NSMutableURLRequest(url: url)
            request.httpMethod = method.rawValue
            do {
                if let requestParameter = parameters {
                    let data = try JSONSerialization.data(withJSONObject: requestParameter, options: JSONSerialization.WritingOptions())
                    let postLength = NSString(format: "%ld", data.count)
                    request.httpBody = data
                    request.addValue(postLength as String, forHTTPHeaderField: "Content-Length")
                }
                request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                request.addValue("ios", forHTTPHeaderField: "device_type")
                request.addValue(FMUserPreferences.getDeviceToken() ?? FMSimulatorToken, forHTTPHeaderField: FMKey.deviceToken)
                request.timeoutInterval = 120.0
                let location = FMLocationManager.shared.getCurrentLocation()
                request.addValue("\(location.coordinate.latitude)", forHTTPHeaderField: "lat")
                request.addValue("\(location.coordinate.longitude)", forHTTPHeaderField: "lng")
                if let authentication = FMUserPreferences.getAccessToken(), authentication.length() > 0 {
                    request.addValue("Bearer \(authentication)", forHTTPHeaderField: "authorization")
                }

            } catch {
                let encodingError = error as NSError
                print("Error could not parse JSON: \(encodingError)")
            }
            
            let task = _session(authentication).dataTask(with: request as URLRequest, completionHandler: {data, response, error -> Void in
                self._handleResponse(data, response, error, onCompletion)
            })
            task.resume()
        }
        else {
            onCompletion(nil, .networkNotAvailable, nil)
        }
    }
    
    func sendMultipartRequest(_ method: Method = .POST, _ urlString: String, _ parameters: [String: Any]? = nil, _ imagesData: [Any]? = nil, _ imageType: ImageType = .jpeg,_ authentication: Bool = false, _ onCompletion: @escaping responseHandler) {
        
        if isInternetReachable() {
            _jsonRequest(urlString, parameters)
            guard let url = URL(string: urlString) else {
                return
            }
            let request = NSMutableURLRequest(url: url)
            request.httpMethod = method.rawValue
            let boundary = _generateBoundaryString()
            let postData =  _createBodyWithParameters(parameters, imagesData, imageType, boundary)
            request.httpBody = postData as Data
            let postLength = NSString(format: "%ld", (postData as Data).count)
            request.addValue(postLength as String, forHTTPHeaderField: "Content-Length")
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.addValue("ios", forHTTPHeaderField: "device_type")
            request.addValue(FMUserPreferences.getDeviceToken() ?? FMSimulatorToken, forHTTPHeaderField: FMKey.deviceToken)
            request.timeoutInterval = 120.0
            let location = FMLocationManager.shared.getCurrentLocation()
            request.addValue("\(location.coordinate.latitude)", forHTTPHeaderField: "lat")
            request.addValue("\(location.coordinate.longitude)", forHTTPHeaderField: "lng")
            if let authentication = FMUserPreferences.getAccessToken(), authentication.length() > 0 {
                request.addValue("Bearer \(authentication)", forHTTPHeaderField: "authorization")
            }
            
            let task = _session(authentication).dataTask(with: request as URLRequest, completionHandler: {data, response, error -> Void in
                self._handleResponse(data, response, error, onCompletion)
            })
            task.resume()
        }
        else {
            onCompletion(nil, .networkNotAvailable, nil)
        }
    }
    
    //MARK:  Private Methods
    private func _session(_ authentication: Bool = false) -> URLSession {
        if authentication {
            let sessionConfiguration: URLSessionConfiguration = URLSessionConfiguration.default
            return URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: nil)
        }
        else {
            return URLSession.shared
        }
    }
    
    private func _jsonRequest(_ urlString: String, _ parameters: [String: Any]? = nil) {
        do {
            if let requestParameter = parameters {
                let jsonData = try JSONSerialization.data(withJSONObject: requestParameter , options: JSONSerialization.WritingOptions.prettyPrinted)
                
                let jsonRequest = NSString(data: jsonData,
                                           encoding: String.Encoding.ascii.rawValue)
                
                print("JSON Request : \(String(describing: jsonRequest))")
            }
            print("URL : \(urlString)")
            
        } catch let error as NSError {
            print(error)
        }
    }
    
    private func _handleResponse(_ data: Data?, _ response: URLResponse?, _ error: Error?, _ onCompletion: @escaping responseHandler) {

        DispatchQueue.main.async {
            guard error == nil else {
                onCompletion(nil, .unknownError, error)
                return
            }
            do {
                guard let httpResponse = (response as? HTTPURLResponse), httpResponse.statusCode == ResponseCode.success.rawValue else {
                    if let httpResponse = (response as? HTTPURLResponse), httpResponse.statusCode == ResponseCode.tokenExpired.rawValue {
                        onCompletion(nil, .tokenExpired, error)
                        return
                    }
                    onCompletion(nil, .unknownError, error)
                    return
                }
                guard let responseData = data else {
                    onCompletion(nil, .unknownError, error)
                    return
                }
                guard let responseDictionary = try JSONSerialization.jsonObject(with: responseData, options: .mutableLeaves) as? NSDictionary else {
                    onCompletion(nil, .unknownError, error)
                    return
                }
                print("Response:\(responseDictionary)")
                guard let status = responseDictionary.value(forKey: "status") as? String, status == "success"  else {
                    if let response = responseDictionary as? [String : Any] {
                        onCompletion(response, .failed , nil)
                    }
                    return
                }
                if let response = responseDictionary as? [String : Any] {
                    onCompletion(response, .success , nil)
                }
            } catch {
                onCompletion(nil, .unknownError, error)
            }
        }
    }
    
    private func _createBodyWithParameters(_ parameters: [String: Any]?,_ imagesData: [Any]?,_ imageType: ImageType, _ boundary: String) -> NSData {
        
        let body = NSMutableData()
        if let requestParameter = parameters {
            for (key, value) in requestParameter {
                body.appendString("--\(boundary)\r\n")
                body.appendString("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
                body.appendString("\(value)\r\n")
            }
        }
        if let dataArray = imagesData {
            for imageData in  dataArray {
                if let imageDatas = imageData as? [String: Data] {
                    for (key, data) in imageDatas {
                        let type = (imageType == .jpeg) ? "jpeg" : "png"
                        let filename = "\(key).\(type)"
                        let mimetype = "image/\(type)"
                        body.appendString("--\(boundary)\r\n")
                        body.appendString("Content-Disposition: form-data; image=\"\(key)\"; filename=\"\(filename)\"\r\n")
                        body.appendString("Content-Type: \(mimetype)\r\n\r\n")
                        body.append(data)
                    }
                }
            }
        }
        body.appendString("\r\n")
        body.appendString("--\(boundary)--\r\n")
        return body
    }
    
    private func _generateBoundaryString() -> String {
        return "Boundary-\(NSUUID().uuidString)"
    }
}

extension FMConnectionManager: URLSessionDelegate {
    
    //MARK:  NSURLSession delegate
    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Swift.Void) {
        
        if challenge.previousFailureCount > 0 {
            completionHandler(.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
        }
        else {
            let credential = URLCredential(user:"", password:"", persistence: .forSession)
            completionHandler(URLSession.AuthChallengeDisposition.useCredential,credential)
        }
    }
    
    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        if let err = error {
            print("Error: \(err.localizedDescription)")
        } else {
            print("Error. Giving up")
        }
    }
}

extension NSMutableData {
    func appendString(_ string: String) {
        if let data = string.data(using: String.Encoding.utf8, allowLossyConversion: true) {
            append(data)
        }
    }
}
