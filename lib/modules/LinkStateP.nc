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
	uint8_t neighborCount;
	// Define LSA structure with uint8_t for everything
	typedef struct LSA {
		uint8_t nodeId;
		uint8_t seqNum;
		uint8_t neighbors[6];
		uint8_t neighborCount;
	} LSA;

	// Function declarations
	void updateLsDatabase(LSA* newLsa);
	void computeRoutes();

	// Global variables
	uint8_t routes[19][2];
	LSA lsDatabase[19];
	uint8_t lsDatabaseSize = 0;
	uint8_t currentSeqNum = 0;
	bool routingInitialized = FALSE;

	command void LinkState.initializeRouting() {
		uint8_t i;
		for(i = 0; i < 19; i++) {
			if (i+1 != TOS_NODE_ID) {
				routes[i][0] = 0xFF;
				routes[i][1] = 0xFF;
			} else {
				routes[i][0] = TOS_NODE_ID;
				routes[i][1] = 0;
			}
		}
		
		lsDatabaseSize = 0;
		currentSeqNum = 0;
		routingInitialized = TRUE;
		
		// Wait longer before sending first LSA to allow neighbor discovery
		call LsTimer.startOneShot(120000);  // 2 minutes first time
		// Then periodic every 60 seconds
		call LsTimer.startPeriodic(60000);
		
		dbg(ROUTING_CHANNEL, "Node %d: Routing initialized, first LSA in 2 minutes\n", TOS_NODE_ID);
	}

	command void LinkState.handleRoutingPacket(uint8_t* buffer, uint8_t len) {
		LSA receivedLsa;
		
		if (len < sizeof(LSA)) {
			dbg(ROUTING_CHANNEL, "Node %d: Invalid LSA size\n", TOS_NODE_ID);
			return;
		}
		
		memcpy(&receivedLsa, buffer, sizeof(LSA));
		
		dbg(ROUTING_CHANNEL, "Node %d: Received LSA from node %d\n", 
			TOS_NODE_ID, receivedLsa.nodeId);
		
		updateLsDatabase(&receivedLsa);
		dbg(ROUTING_CHANNEL,"Calling computeRoutes()\n");
		computeRoutes();
	}

	command void LinkState.startRouting() {
		LSA myLsa;
//		uint8_t neighborCount;
		uint8_t i;
		uint16_t neighbor;
		dbg(ROUTING_CHANNEL,"startRouting() running\n");
		
		if (!routingInitialized) {
			return;
		}
	
		neighborCount = call NeighborDiscovery.getNeighborCount();

		if (neighborCount == 0) {
			dbg(ROUTING_CHANNEL, "Node %d: No neighbors yet, skipping LSA\n", TOS_NODE_ID);
			return;
		}

		myLsa.nodeId = TOS_NODE_ID;
		myLsa.seqNum = currentSeqNum++;
		
		dbg(ROUTING_CHANNEL, "Node %d: NeighborDiscovery returned %d neighbors\n", TOS_NODE_ID, neighborCount);

		myLsa.neighborCount = (neighborCount > 6) ? 6 : neighborCount;
		
		for(i = 0; i < myLsa.neighborCount; i++) {
			neighbor = call NeighborDiscovery.getNeighbor(i);
			dbg(ROUTING_CHANNEL, "Node %d: Neighbor[%d] = %d\n", 
				TOS_NODE_ID, i, neighbor);
			myLsa.neighbors[i] = neighbor;
		}
		
		dbg(ROUTING_CHANNEL, "Node %d: sizeof(LSA)=%d, should be 9\n", TOS_NODE_ID, sizeof(LSA));

		if (sizeof(LSA) != 9) {
			dbg(ROUTING_CHANNEL, "Node %d: ERROR - LSA size is wrong!\n", TOS_NODE_ID);
		}
		
		call Flooding.startFlood(0, (uint8_t*)&myLsa, sizeof(LSA), PROTOCOL_LINKSTATE);
	}

	command void LinkState.printLinkState() {
		uint8_t i;
		uint8_t j;
		
		dbg(GENERAL_CHANNEL, "=== Node %d Link State ===\n", TOS_NODE_ID);
		
		for(i = 0; i < lsDatabaseSize; i++) {
			dbg(GENERAL_CHANNEL, "LSA[%d]: Node %d, Neighbors: ", 
				i, lsDatabase[i].nodeId);
			for(j = 0; j < lsDatabase[i].neighborCount; j++) {
				dbg(GENERAL_CHANNEL, "%d ", lsDatabase[i].neighbors[j]);
			}
			dbg(GENERAL_CHANNEL, "\n");
		}
		dbg(GENERAL_CHANNEL, "=== End Link State ===\n");
	}

	command void LinkState.printRouteTable() {
		uint8_t i;
		uint8_t routeCount = 0;
		
		dbg(GENERAL_CHANNEL, "=== Node %d Routing Table ===\n", TOS_NODE_ID);
		
		for(i = 0; i < 19; i++) {
			if(routes[i][0] != 0xFF) {
				dbg(GENERAL_CHANNEL, "Dest %d -> NextHop %d, Cost %d\n", 
					i+1, routes[i][0], routes[i][1]);
				routeCount++;
			}
		}
		
		if (routeCount == 0) {
			dbg(GENERAL_CHANNEL, "No routes in table\n");
		}
		
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
		uint8_t neighborCount;
		uint8_t i;
		uint8_t j;
		uint16_t neighbor;
		LSA* lsa;
		uint8_t lsaNeighbor;
		uint8_t newCost;
		
		for(i = 0; i < 19; i++) {
			routes[i][0] = 0xFF;
			routes[i][1] = 0xFF;
		}
		
		if(TOS_NODE_ID >= 1 && TOS_NODE_ID <= 19) {
			routes[TOS_NODE_ID-1][0] = TOS_NODE_ID;
			routes[TOS_NODE_ID-1][1] = 0;
		}
		
		neighborCount = call NeighborDiscovery.getNeighborCount();
		dbg(ROUTING_CHANNEL,"getNeighborCount called, count is: %d\n",neighborCount);
		for(i = 0; i < neighborCount; i++) {
			neighbor = call NeighborDiscovery.getNeighbor(i);
			dbg(ROUTING_CHANNEL,"getNeighbor called\n");
			if(neighbor >= 1 && neighbor <= 19) {
				routes[neighbor-1][0] = neighbor;
				routes[neighbor-1][1] = 1;
			}
		}
		
		for(i = 0; i < lsDatabaseSize; i++) {
			lsa = &lsDatabase[i];
			
			for(j = 0; j < lsa->neighborCount; j++) {
				lsaNeighbor = lsa->neighbors[j];
				if(lsaNeighbor >= 1 && lsaNeighbor <= 19) {
					if(routes[lsa->nodeId-1][0] != 0xFF) {
						newCost = routes[lsa->nodeId-1][1] + 1;
						if(newCost < routes[lsaNeighbor-1][1]) {
							routes[lsaNeighbor-1][0] = routes[lsa->nodeId-1][0];
							routes[lsaNeighbor-1][1] = newCost;
						}
					}
				}
			}
		}
		
		dbg(ROUTING_CHANNEL, "Node %d: Routes computed\n", TOS_NODE_ID);
	}

	event void LsTimer.fired() {
		call LinkState.startRouting();
	}

	event void Flooding.floodReceived(uint16_t floodSource, uint16_t seqNum, uint8_t *payld, uint8_t payldLen) {
	}

	event void Flooding.floodAckReceived(uint16_t source, uint16_t seq) {
	}

	event void NeighborDiscovery.neighborsChanged(uint8_t externalNeighborCount){
		//I was hoping that this would be extremely useful, but the code appears to outright do nothing.
		//when the event is signaled from NeighborDiscoveryP.nc, these lines of code are never executed.
//		dbg(ROUTING_CHANNEL,"neighborsChanged successfully signaled\n");
//		neighborCount = externalNeighborCount;
//		dbg(ROUTING_CHANNEL,"neighborCount changed, it is now: %d\n",neighborCount);
	}
}