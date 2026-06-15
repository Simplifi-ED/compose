import Foundation

@objc(ComposeXPCProtocol)
package protocol ComposeXPCProtocol {
    func status(requestJSON: String, reply: @escaping (String?, NSError?) -> Void)
    func ps(requestJSON: String, reply: @escaping (String?, NSError?) -> Void)
    func up(requestJSON: String, reply: @escaping (String?, NSError?) -> Void)
    func down(requestJSON: String, reply: @escaping (String?, NSError?) -> Void)
}
