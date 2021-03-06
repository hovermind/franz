//
//  Consumer.swift
//  Pods
//
//  Created by Kellan Cummings on 2/5/16.
//
//

import Foundation


/**
A consumer that listens to and consumes messages from certain topics.
All consumers belong to a group.
Do not initialize a `Consumer` instance directly, instead use `Cluster.getConsumer(topics: groupId:)`
- SeeAlso: `Cluster.getConsumer(topics: groupId:)`
*/
public class Consumer {
	private let cluster: Cluster
	internal var broker: Broker?
	internal var membership: GroupMembership?
	internal let joinedGroupSemaphore = DispatchSemaphore(value: 0)
	
	var groupOffsetsTimer: Timer!
	var heartbeatTimer: Timer!
	
	internal init(cluster: Cluster, groupId: String) {
		self.cluster = cluster
		
		if #available(OSX 10.12, iOS 10, tvOS 10, watchOS 3, *) {
			groupOffsetsTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in self.commitGroupoffsets() }
			heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in self.sendHeartbeat() }
		} else {
			// Fallback on earlier versions
			groupOffsetsTimer = Timer.scheduledTimer(timeInterval: 5, target: self, selector: #selector(commitGroupoffsets), userInfo: nil, repeats: true)
			heartbeatTimer =  Timer.scheduledTimer(timeInterval: 3, target: self, selector: #selector(sendHeartbeat), userInfo: nil, repeats: true)
		}
	}
	
	private let listenQueue = DispatchQueue(label: "FranzConsumerListenQueue")
	
	var offsetsToCommit = [TopicName: [PartitionId: (Offset, OffsetMetadata?)]]()
	@objc private func commitGroupoffsets() {
		guard let groupId = self.membership?.group.id, let broker = self.broker else { return }
		broker.commitGroupOffset(groupId: groupId, topics: offsetsToCommit)
	}
	
	@objc private func sendHeartbeat() {
		guard let groupId = self.membership?.group.id,
			let generationId = self.membership?.group.generationId,
			let memberId = self.membership?.memberId else {
				return
		}
		self.broker?.heartbeatRequest(groupId, generationId: generationId, memberId: memberId)
	}
	
	/**
	Returns messages from the topics that the consumer is subscribed to.

	- parameters:
		- fromStart: If true the consumer will call the handler for all existing messages, and if false the consumer will only call the handler for new messages.
		- handler: Called whenever a message is received, along with that message.
	*/
	public func listen(fromStart: Bool = true, handler: @escaping (Message) -> Void) {
		if listening {
			fatalError("Cannot listen multiple times from the same consumer")
		} else {
			listening = true
		}
		listenQueue.async {
			self.joinedGroupSemaphore.wait()
			guard let membership = self.membership, let broker = self.broker else {
				return
			}
			
			self.cluster.getParitions(for: Array(membership.group.topics)) { partitions in
				let ids = partitions.reduce([TopicName: [PartitionId]](), { (result, arg1) in
					let (key, value) = arg1
					var copy = result
					copy[key] = value.map { $0.id }
					return copy
				})
				
				self.cancelToken = broker.poll(topics: ids, fromStart: fromStart, groupId: membership.group.id, replicaId: ReplicaId.none, callback: { topic, partitionId, offset, messages in
					messages.forEach(handler)
					
					if var topicOffsets = self.offsetsToCommit[topic] {
						topicOffsets[partitionId] = (offset, nil)
					} else {
						self.offsetsToCommit[topic] = [partitionId: (offset, nil)]
					}
				}, errorCallback: { error in
					print("Error polling: \(error.localizedDescription)")
				})
			}
		}
	}

	private var cancelToken: Broker.CancelToken?
	
	private var listening = false
	
	/**
	Stops listening for incoming messages if `listen` was called.
	*/
	public func stop() {
		cancelToken?.cancel()
		listening = false
		groupOffsetsTimer.invalidate()
		heartbeatTimer.invalidate()
	}
}
