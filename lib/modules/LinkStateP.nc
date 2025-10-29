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
	// Define LSA structure with uint8_t for everything
		typedef struct LSA {
		uint8_t nodeId;
		uint8_t seqNum;
		uint8_t neighborCount;
		uint8_t neighbors[6];
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
		
		//dbg(ROUTING_CHANNEL, "Node %d: Routing initialized, first LSA in 2 minutes\n", TOS_NODE_ID);
	}

	command void LinkState.handleRoutingPacket(uint8_t* buffer, uint8_t len) {
		LSA receivedLsa;
		
		if (len < sizeof(LSA)) {
			//dbg(ROUTING_CHANNEL, "Node %d: Invalid LSA size\n", TOS_NODE_ID);
			return;
		}
		
		memcpy(&receivedLsa, buffer, sizeof(LSA));
		
//      dbg(ROUTING_CHANNEL, "Node %d: Received LSA from node %d\n", 
//          TOS_NODE_ID, receivedLsa.nodeId);
		
		updateLsDatabase(&receivedLsa);
		//dbg(ROUTING_CHANNEL,"Calling computeRoutes()\n");
		computeRoutes();
	}

	command void LinkState.startRouting() {
		LSA myLsa;
		uint8_t i;
		uint16_t neighbor;
		uint8_t currentNeighborCount;
		//dbg(ROUTING_CHANNEL,"startRouting() running\n");
		
		if (!routingInitialized) {
			return;
		}
	
		currentNeighborCount = call NeighborDiscovery.getNeighborCount();

		if (currentNeighborCount == 0) {
//          dbg(ROUTING_CHANNEL, "Node %d: No neighbors yet, skipping LSA\n", TOS_NODE_ID);
			return;
		}

		myLsa.nodeId = TOS_NODE_ID;
		myLsa.seqNum = currentSeqNum++;
		
		//dbg(ROUTING_CHANNEL, "Node %d: NeighborDiscovery returned %d neighbors\n", TOS_NODE_ID, currentNeighborCount);

		myLsa.neighborCount = (currentNeighborCount > 19) ? 19 : currentNeighborCount;
//      dbg(ROUTING_CHANNEL, "NeighborCount is %d\n", myLsa.neighborCount);

		for(i = 0; i < myLsa.neighborCount; i++) {
			neighbor = call NeighborDiscovery.getNeighbor(i);
			//dbg(ROUTING_CHANNEL, "Node %d: Neighbor[%d] = %d\n", 
//             TOS_NODE_ID, i, neighbor);
			myLsa.neighbors[i] = neighbor;
		}
		
		//dbg(ROUTING_CHANNEL, "Node %d: sizeof(LSA)=%d, should be 9\n", TOS_NODE_ID, sizeof(LSA));

		if (sizeof(LSA) != 9) {
			//dbg(ROUTING_CHANNEL, "Node %d: ERROR - LSA size is wrong!\n", TOS_NODE_ID);
		}
		
		call Flooding.startFlood(0, (uint8_t*)&myLsa, sizeof(LSA), PROTOCOL_LINKSTATE);
	}

	command void LinkState.printLinkState() {
		uint8_t i;
		uint8_t j;
		
		dbg(GENERAL_CHANNEL, "=== Node %d Link State ===\n", TOS_NODE_ID);
		
		for(i = 0; i < lsDatabaseSize; i++) {
			dbg(GENERAL_CHANNEL, "LSA[%d]: Node %d, Neighbors: \n", 
				i, lsDatabase[i].nodeId);
			for(j = 0; j < lsDatabase[i].neighborCount; j++) {
				dbg(GENERAL_CHANNEL, "%d \n", lsDatabase[i].neighbors[j]);
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
					if(TOS_NODE_ID==19){
						dbg(ROUTING_CHANNEL, "Node 19 updating LSA for node %d with seq %d\n", newLsa->nodeId, newLsa->seqNum);
					}
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
		uint16_t neighbor;
		uint8_t currentNodeId = TOS_NODE_ID;
		uint8_t currentNeighborCount;
		uint8_t updated;
		uint8_t nodeId;
		uint8_t neighborId;
		uint8_t newCost;
		
		// Initialize all routes to unreachable
		for(i = 0; i < 19; i++) {
			routes[i][0] = 0xFF;  // Next hop
			routes[i][1] = 0xFF;  // Cost (255 means unreachable)
		}
		
		// Distance to self is 0
		if(currentNodeId >= 1 && currentNodeId <= 19) {
			routes[currentNodeId-1][0] = currentNodeId;
			routes[currentNodeId-1][1] = 0;
		}
		
		// Initialize direct neighbors
		currentNeighborCount = call NeighborDiscovery.getNeighborCount();
		for(i = 0; i < currentNeighborCount; i++) {
			neighbor = call NeighborDiscovery.getNeighbor(i);
			if(neighbor >= 1 && neighbor <= 19) {
				routes[neighbor-1][0] = neighbor;  // Next hop is the neighbor itself
				routes[neighbor-1][1] = 1;         // Cost is 1 hop
			}
		}
		
		// Main Dijkstra loop - continue until no more updates
		do {
			updated = FALSE;
			
			// For each node in our LS database
			for(i = 0; i < lsDatabaseSize; i++) {
				nodeId = lsDatabase[i].nodeId;
				
				// If we don't have a route to this node yet, skip it
				if(routes[nodeId-1][0] == 0xFF) {
					continue;
				}
				
				// For each neighbor of this node
				for(j = 0; j < lsDatabase[i].neighborCount; j++) {
					neighborId = lsDatabase[i].neighbors[j];
					
					// Skip if neighbor is out of range
					if(neighborId < 1 || neighborId > 19) {
						continue;
					}
					
					// Skip if we're trying to route to ourselves
					if(neighborId == currentNodeId) {
						continue;
					}
					
					// Calculate new cost through this path
					newCost = routes[nodeId-1][1] + 1;
					
					// If this path is better than what we have, update
					if(newCost < routes[neighborId-1][1]) {
						routes[neighborId-1][0] = routes[nodeId-1][0];  // Next hop is same as to the intermediate node
						routes[neighborId-1][1] = newCost;
						updated = TRUE;
					}
				}
			}
		} while(updated);
		
		//dbg(ROUTING_CHANNEL, "Node %d: Dijkstra routes computed\n", TOS_NODE_ID);
	}

	command uint8_t LinkState.getNextHop(uint8_t destination){
		return routes[destination-1][0];
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
		//dbg(ROUTING_CHANNEL,"neighborsChanged successfully signaled\n");
		//neighborCount = externalNeighborCount;
		//dbg(ROUTING_CHANNEL,"neighborCount changed, it is now: %d\n",neighborCount);
	}
}