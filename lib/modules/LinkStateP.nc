#include <Timer.h>
#include "../../includes/CommandMsg.h"
#include "../../includes/command.h"
#include "../../includes/channels.h"
#include "../../includes/flooding.h"
#include "../../includes/packet.h"
#include "../../includes/sendInfo.h"

module LinkStateP{
	provides interface LinkState;

	uses interface Queue<sendInfo*>;
	uses interface Pool<sendInfo>;
	uses interface SimpleSend;
	uses interface NeighborDiscovery;
	uses interface Flooding;
	uses interface Timer<TMilli> as LsTimer;
}

implementation {
	// Define LSA structure
	typedef struct LSA {
		uint8_t nodeId;
		uint8_t seqNum;
		uint8_t neighborCount;
		uint8_t neighbors[6];
	} LSA;

	// Function declarations
	void updateLsDatabase(LSA* newLsa);
	void computeRoutes();
	bool hasCompleteTopology();

	// Global variables
	uint8_t routes[19][2];  // [nextHop, cost] for nodes 1-19
	LSA lsDatabase[19];		//most recent link state information from all other nodes
	uint8_t lsDatabaseSize = 0;
	uint8_t currentSeqNum = 0;
	bool routingInitialized = FALSE;

	command void LinkState.initializeRouting() {
		uint8_t i;
		for(i = 0; i < 19; i++) {
			routes[i][0] = 0xFF;
			routes[i][1] = 0xFF;
		}//start with all routes going through an impossible node for an infinite distance
		
		if(TOS_NODE_ID >= 1 && TOS_NODE_ID <= 19) {
			routes[TOS_NODE_ID-1][0] = TOS_NODE_ID;
			routes[TOS_NODE_ID-1][1] = 0;
		}//we're one hop from ourselves!
		
		lsDatabaseSize = 0;
//		currentSeqNum = 0;
		routingInitialized = TRUE;

		//setting for one minute to allow NeighborDiscovery to happen before we route again.
//		call LsTimer.startOneShot(60000);

		// Wait longer before sending first LSA to allow neighbor discovery
		call LsTimer.startOneShot(120000);  // 2 minutes first time
		// Then periodic every 60 seconds
		call LsTimer.startPeriodic(60000);
		
		//dbg(ROUTING_CHANNEL, "Node %d: Routing initialized, first LSA in 2 minutes\n", TOS_NODE_ID);
	}

	command void LinkState.handleRoutingPacket(uint8_t* buffer, uint8_t len) {
		LSA receivedLsa;
		
		//if we don't actually have all the information we're looking for, bail.
		if (len < sizeof(LSA)) {
			return;
		}
		//otherwise copy it into memory, update our database and routes.
		memcpy(&receivedLsa, buffer, sizeof(LSA));
		updateLsDatabase(&receivedLsa);
		computeRoutes();
	}

	command void LinkState.startRouting() {
		LSA myLsa;
		uint8_t i;
		uint16_t neighbor;
		uint8_t currentNeighborCount;
		
		if (!routingInitialized) {
			return;
		}
	
		//get our number of neighbors and assemble our packet
		currentNeighborCount = call NeighborDiscovery.getNeighborCount();

		myLsa.nodeId = TOS_NODE_ID;
		myLsa.seqNum = currentSeqNum++;
		//we're maxing out at 6 neighbors, we want to conserve packet space.
		//not sure if we could get away with increasing this number, but for these topologies this is enough anyway.
		myLsa.neighborCount = (currentNeighborCount > 6) ? 6 : currentNeighborCount;

		//copy our neighbors' IDs into the packet to be sent.
		for(i = 0; i < myLsa.neighborCount; i++) {
			neighbor = call NeighborDiscovery.getNeighbor(i);
			myLsa.neighbors[i] = neighbor;
		}
		//and simply flood it, as expected.
		call Flooding.startFlood(0, (uint8_t*)&myLsa, sizeof(LSA), PROTOCOL_LINKSTATE);
	}

	command void LinkState.printLinkState() {
		uint8_t i, j;
		char neighborStr[50];
		
		dbg(GENERAL_CHANNEL, "=== Node %d Link State Database ===\n", TOS_NODE_ID);
		dbg(GENERAL_CHANNEL, "Database size: %d entries\n", lsDatabaseSize);
		
		for(i = 0; i < lsDatabaseSize; i++) {
			neighborStr[0] = '\0';
			for(j = 0; j < lsDatabase[i].neighborCount; j++) {
				char temp[6];
				sprintf(temp, "%d ", lsDatabase[i].neighbors[j]);
				strcat(neighborStr, temp);
			}//intelligently assembling strings and printing
			
			dbg(GENERAL_CHANNEL, "LSA[%d]: Node %d, Seq %d, Neighbors: %s\n", 
				i, lsDatabase[i].nodeId, lsDatabase[i].seqNum, neighborStr);
		}

//This is cool and useful, but we have it hardcoded to only work for a topology with 19 nodes,
//so for any smaller number it will just always say no.		
//		dbg(GENERAL_CHANNEL, "Complete topology: %s\n", 
//			hasCompleteTopology() ? "YES" : "NO");
		dbg(GENERAL_CHANNEL, "=== End Link State ===\n");
	}

	command void LinkState.printRouteTable() {
		uint8_t i;
		uint8_t reachableCount = 0;
		
		dbg(GENERAL_CHANNEL, "=== Node %d Routing Table ===\n", TOS_NODE_ID);
		
		for(i = 0; i < 19; i++) {//hardcoding to 19 means that we'll have some empty "UNREACHABLEs" in smaller topologies,
								 //but that's even more harmless than the "Complete topology" above, I think.
			uint8_t nodeId = i + 1;
			if(routes[i][0] != 0xFF) {//if it's not 0xFF, we actually have a route to it.
				dbg(GENERAL_CHANNEL, "Dest %d -> NextHop %d, Cost %d\n", 
					nodeId, routes[i][0], routes[i][1]);
				reachableCount++;
			} else {
				dbg(GENERAL_CHANNEL, "Dest %d -> UNREACHABLE\n", nodeId);
			}
		}
		
		dbg(GENERAL_CHANNEL, "Reachable: %d/19 nodes\n", reachableCount);
		dbg(GENERAL_CHANNEL, "=== End Route Table ===\n");
	}

	void updateLsDatabase(LSA* newLsa) {
		uint8_t i;
	
		for(i = 0; i < lsDatabaseSize; i++) {
			if(lsDatabase[i].nodeId == newLsa->nodeId) {
				//if our current packet is the newest from its node, make it the current entry in the db.
				if(newLsa->seqNum > lsDatabase[i].seqNum) {
					memcpy(&lsDatabase[i], newLsa, sizeof(LSA));
				}
				return;
			}
		}
		
		if(lsDatabaseSize < 19) {
			memcpy(&lsDatabase[lsDatabaseSize], newLsa, sizeof(LSA));
			lsDatabaseSize++;
		}
	}

	void computeRoutes() {
		uint8_t i, j;
		uint8_t currentNodeId = TOS_NODE_ID;
		uint8_t updated;
		uint8_t pass;
		uint8_t neighborCount;
		uint16_t neighbor;
		uint8_t nodeId;
		uint8_t neighborId;
		uint8_t costToNode;
		uint8_t newCost;
		
		for(i = 0; i < 19; i++) {
			routes[i][0] = 0xFF;
			routes[i][1] = 0xFF;
		}//start by setting all routes to "infinity"
		
		if(currentNodeId >= 1 && currentNodeId <= 19) {
			routes[currentNodeId-1][0] = currentNodeId;
			routes[currentNodeId-1][1] = 0;
		}//except for the path to ourselves, of course.
		
		neighborCount = call NeighborDiscovery.getNeighborCount();
		for(i = 0; i < neighborCount; i++) {
			neighbor = call NeighborDiscovery.getNeighbor(i);
			if(neighbor >= 1 && neighbor <= 19) {
				routes[neighbor-1][0] = neighbor;
				routes[neighbor-1][1] = 1;
			}
		}//for each of our direct neighbors, we can reach them with a path length of 1.
		
		for(pass = 0; pass < 25; pass++) {
			updated = FALSE;
			
			for(i = 0; i < lsDatabaseSize; i++) {
				nodeId = lsDatabase[i].nodeId;
				
				if(nodeId < 1 || nodeId > 19 || routes[nodeId-1][0] == 0xFF) {
					continue;
				}
				
				costToNode = routes[nodeId-1][1];
				if(costToNode == 0xFF) continue;
				//for each node in our database that we can reach, look at each of its neighbors, and recognize that we can reach its neighbors with one more
				//step than we can reach the node itself.
				for(j = 0; j < lsDatabase[i].neighborCount; j++) {
					neighborId = lsDatabase[i].neighbors[j];
					
					if(neighborId < 1 || neighborId > 19 || neighborId == currentNodeId) {
						continue;
					}
					
					newCost = costToNode + 1;
					//once we've calculated a hypothetical path to those neighbors, see if it actually is better than what we had before,
					//and update our table if so.
					if(newCost < 100 && newCost < routes[neighborId-1][1]) {
						routes[neighborId-1][0] = routes[nodeId-1][0];
						routes[neighborId-1][1] = newCost;
						updated = TRUE;
					}
				}
			}
			
			if(!updated) {
				break;
			}//we're trying this a bunch of times to let the changes propogate through the system.
			//if we make a pass through the whole database and nothing changes, we've converged and we can stop.
		}
	}

	bool hasCompleteTopology() {
		//this just returns true if we can reach every node from a given node.
		//as it stands, we're hardcoded to the value 19, so this is fairly worthless for any topologies of other sizes.
		uint8_t nodePresence[19] = {0};
		uint8_t i;
		
		if(TOS_NODE_ID >= 1 && TOS_NODE_ID <= 19) {
			nodePresence[TOS_NODE_ID-1] = 1;
		}
		
		for(i = 0; i < lsDatabaseSize; i++) {
			if(lsDatabase[i].nodeId >= 1 && lsDatabase[i].nodeId <= 19) {
				nodePresence[lsDatabase[i].nodeId-1] = 1;
			}
		}
		
		for(i = 0; i < 19; i++) {
			if(!nodePresence[i]) {
				return FALSE;
			}
		}
		return TRUE;
	}

	command uint8_t LinkState.getNextHop(uint8_t destination){
		//returns the next hop that a packet should take from the current node to the given destination.
		if(destination >= 1 && destination <= 19) {
			return routes[destination-1][0];
		}
		return 0xFF;
	}

	event void LsTimer.fired() {
		call LinkState.startRouting();
	}

	event void Flooding.floodReceived(uint16_t floodSource, uint16_t seqNum, uint8_t *payld, uint8_t payldLen) {
	}

	event void Flooding.floodAckReceived(uint16_t source, uint16_t seq) {
	}

	event void NeighborDiscovery.neighborsChanged(uint8_t externalNeighborCount){
		call LinkState.startRouting();
	}
}