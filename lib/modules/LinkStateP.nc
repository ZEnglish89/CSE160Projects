
//again, start with the same includes as FloodingP.nc, we can make changes as necessary later but
//this is a useful baseline
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
	uses interface Pool<sendInfo*>;

	//we may or may not need this? Flooding might just handle
	//everything we would otherwise use this for, but I'm not sure yet so we
	//may as well include it for now.
	uses interface SimpleSend;

	uses interface NeighborDiscovery;

//	uses interface Flooding;
}

implementation{

	//allocating space for 19 total nodes,
	//because that's how many the largest topography has.
	const uint8_t numNodes = 19;
	//we're going to use this as a hash table, where the index [destNodeID-1][0] will
	//contain the value [nextHopID], that way we can just forward packets to the value
	//of the table
	//[destNodeID-1][1] will contain the length of the path, so that we can implement Dijkstra's.
	uint16_t routes[19][2];

	command void LinkState.initializeRouting(){
		//setting up initial values for the routing table.
		uint8_t i;
		for(i = 0;i<numNodes;i++){
			if (i+1!=TOS_NODE_ID){
				//we will use [numNodes+1] to signify an unknown length or a node that's not in the table, since you can never route through a
				//node that doesn't exist. We'll just need to include checks for this later, of course.
				routes[i][0] = numNodes+1;
				//similarly, -1 will represent an infinite path length, for those nodes that are not known yet.
				routes[i][1] = -1;
			}
			//if the current node is ourselves, we simply show that we route it to ourselves and note a length of zero.
			else{
				routes[i][0] = TOS_NODE_ID;
				routes[i][1] = 0;
			}
		}
		dbg(ROUTING_CHANNEL,"Routing table set up for node %d\n",TOS_NODE_ID);
	}

}