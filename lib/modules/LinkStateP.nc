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
	LSA lsDatabase[19];
	uint8_t lsDatabaseSize = 0;
	uint8_t currentSeqNum = 0;
	bool routingInitialized = FALSE;

	command void LinkState.initializeRouting() {
		uint8_t i;
		for(i = 0; i < 19; i++) {
			routes[i][0] = 0xFF;
			routes[i][1] = 0xFF;
		}
		
		if(TOS_NODE_ID >= 1 && TOS_NODE_ID <= 19) {
			routes[TOS_NODE_ID-1][0] = TOS_NODE_ID;
			routes[TOS_NODE_ID-1][1] = 0;
		}
		
		lsDatabaseSize = 0;
		currentSeqNum = 0;
		routingInitialized = TRUE;
		
		call LsTimer.startOneShot(3000);
		call LsTimer.startPeriodic(15000);
	}

	command void LinkState.handleRoutingPacket(uint8_t* buffer, uint8_t len) {
		LSA receivedLsa;
		
		if (len < sizeof(LSA)) {
			return;
		}
		
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
	
		currentNeighborCount = call NeighborDiscovery.getNeighborCount();

		myLsa.nodeId = TOS_NODE_ID;
		myLsa.seqNum = currentSeqNum++;
		myLsa.neighborCount = (currentNeighborCount > 6) ? 6 : currentNeighborCount;

		for(i = 0; i < myLsa.neighborCount; i++) {
			neighbor = call NeighborDiscovery.getNeighbor(i);
			myLsa.neighbors[i] = neighbor;
		}
		
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
			}
			
			dbg(GENERAL_CHANNEL, "LSA[%d]: Node %d, Seq %d, Neighbors: %s\n", 
				i, lsDatabase[i].nodeId, lsDatabase[i].seqNum, neighborStr);
		}
		
		dbg(GENERAL_CHANNEL, "Complete topology: %s\n", 
			hasCompleteTopology() ? "YES" : "NO");
		dbg(GENERAL_CHANNEL, "=== End Link State ===\n");
	}

	command void LinkState.printRouteTable() {
		uint8_t i;
		uint8_t reachableCount = 0;
		
		dbg(GENERAL_CHANNEL, "=== Node %d Routing Table ===\n", TOS_NODE_ID);
		
		for(i = 0; i < 19; i++) {
			uint8_t nodeId = i + 1;
			if(routes[i][0] != 0xFF) {
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
		}
		
		if(currentNodeId >= 1 && currentNodeId <= 19) {
			routes[currentNodeId-1][0] = currentNodeId;
			routes[currentNodeId-1][1] = 0;
		}
		
		neighborCount = call NeighborDiscovery.getNeighborCount();
		for(i = 0; i < neighborCount; i++) {
			neighbor = call NeighborDiscovery.getNeighbor(i);
			if(neighbor >= 1 && neighbor <= 19) {
				routes[neighbor-1][0] = neighbor;
				routes[neighbor-1][1] = 1;
			}
		}
		
		for(pass = 0; pass < 25; pass++) {
			updated = FALSE;
			
			for(i = 0; i < lsDatabaseSize; i++) {
				nodeId = lsDatabase[i].nodeId;
				
				if(nodeId < 1 || nodeId > 19 || routes[nodeId-1][0] == 0xFF) {
					continue;
				}
				
				costToNode = routes[nodeId-1][1];
				if(costToNode == 0xFF) continue;
				
				for(j = 0; j < lsDatabase[i].neighborCount; j++) {
					neighborId = lsDatabase[i].neighbors[j];
					
					if(neighborId < 1 || neighborId > 19 || neighborId == currentNodeId) {
						continue;
					}
					
					newCost = costToNode + 1;
					
					if(newCost < 100 && newCost < routes[neighborId-1][1]) {
						routes[neighborId-1][0] = routes[nodeId-1][0];
						routes[neighborId-1][1] = newCost;
						updated = TRUE;
					}
				}
			}
			
			if(!updated) {
				break;
			}
		}
	}

	bool hasCompleteTopology() {
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
		computeRoutes();
	}
}