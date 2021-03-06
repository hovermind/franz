//
//  PlainMechanism.swift
//  Franz
//
//  Created by Luke Lau on 15/04/2018.
//

import Foundation

/// Handles authenticating with the PLAIN mechanism
struct PlainMechanism: SaslMechanism {
	
	let username: String
	let password: String
	
	var kafkaLabel: String {
		return "PLAIN"
	}
	
	func authenticate(connection: Connection) -> Bool {
		let zid = ""
		guard let data = [zid, username, password].joined(separator: "\0").data(using: .utf8) else {
			fatalError("Plain authentication failed, make sure username and password are UTF8 encoded")
		}
		let authRequest = SaslAuthenticateRequest(saslAuthBytes: data)
		guard let response = connection.writeBlocking(authRequest) else {
			return false
		}
		return response.errorCode == 0
	}
}
