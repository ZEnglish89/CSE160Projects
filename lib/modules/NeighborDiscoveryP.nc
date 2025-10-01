#include <Timer.h>
#include "../../includes/packet.h"
#include "../../includes/sendInfo.h"
#include "../../includes/channels.h"

generic module NeighborDiscoveryP() {
    provides interface NeighborDiscovery;

    uses interface Timer<TMilli> as neighborTimer;
    uses interface Random;

    uses interface Queue<sendInfo*>;
    uses interface Pool<sendInfo>;

    uses interface SimpleSend;
}

implementation {
    uint16_t neighbors[19];
    uint8_t neighborCount = 0;
    bool discoveryActive = FALSE;
    
    // Declare the task first
    task void search();
    
    // Initialize neighbor table
    void initializeNeighborTable() {
        uint8_t i;
        neighborCount = 0;
        for(i = 0; i < 19; i++) {
            neighbors[i] = 0;
        }
        dbg(NEIGHBOR_CHANNEL, "Neighbor table initialized\n");
    }
    
    command void NeighborDiscovery.findNeighbors() {
        uint32_t nodeDelay;
        
        discoveryActive = TRUE;
        initializeNeighborTable();
        
        // Calculate delay based on node ID - lower nodes send first
        // Use 30 seconds (30000ms) between nodes to spread them out
        nodeDelay = (TOS_NODE_ID - 1) * 30000; // 30 seconds between each node
        
        // Start timer with node-ID-based delay
        call neighborTimer.startOneShot(nodeDelay);
        dbg(NEIGHBOR_CHANNEL, "Node %d will start discovery in %lu ms\n", TOS_NODE_ID, nodeDelay);
    }
   
    task void search() {
        pack discoveryMsg;
        uint8_t payload[14];
        
        if(!discoveryActive) return;
        
        dbg(NEIGHBOR_CHANNEL, "Node %d starting neighbor search\n", TOS_NODE_ID);
        
        // Create and send a neighbor discovery packet
        discoveryMsg.src = TOS_NODE_ID;
        discoveryMsg.dest = AM_BROADCAST_ADDR;
        discoveryMsg.TTL = 1;
        discoveryMsg.protocol = 1;
        
        // Use a special payload to identify neighbor discovery packets
        memcpy(payload, "NEIGHBOR_DISC", 13);
        payload[13] = '\0';
        memcpy(discoveryMsg.payload, payload, 14);
        
        // Send the discovery message
        call SimpleSend.send(discoveryMsg, AM_BROADCAST_ADDR);
        
        dbg(NEIGHBOR_CHANNEL, "Node %d sent neighbor discovery packet\n", TOS_NODE_ID);
        
        // Schedule next discovery in 30 seconds (30000 milliseconds)
        call neighborTimer.startOneShot(30000);
        dbg(NEIGHBOR_CHANNEL, "Node %d scheduled next discovery in 30 seconds\n", TOS_NODE_ID);
    }

    // Add a function to add neighbors to the table
    void addNeighbor(uint16_t nodeId) {
        // Check if neighbor already exists
        uint8_t i;
        for(i = 0; i < neighborCount; i++) {
            if(neighbors[i] == nodeId) {
                dbg(NEIGHBOR_CHANNEL, "Node %d: Neighbor %d already in table, skipping\n", TOS_NODE_ID, nodeId);
                return; // Neighbor already in table
            }
        }
        
        // Add new neighbor if there's space
        if(neighborCount < 19) {
            neighbors[neighborCount] = nodeId;
            neighborCount++;
            dbg(NEIGHBOR_CHANNEL, "Node %d added neighbor %d. Total neighbors: %d\n", TOS_NODE_ID, nodeId, neighborCount);
        } else {
            dbg(NEIGHBOR_CHANNEL, "Node %d neighbor table full, cannot add %d\n", TOS_NODE_ID, nodeId);
        }
    }

    event void neighborTimer.fired() {
        dbg(NEIGHBOR_CHANNEL, "Node %d neighbor timer fired\n", TOS_NODE_ID);
        post search();
    }

    command void NeighborDiscovery.neighborUpdate(uint16_t nodeId) {
        addNeighbor(nodeId);
        // Comment out this debug to reduce spam, since it's called frequently
        // dbg(NEIGHBOR_CHANNEL, "Node %d neighbor update: Added node %d\n", TOS_NODE_ID, nodeId);
    }

    command void NeighborDiscovery.printNeighbors() {
        uint8_t i;
        dbg(GENERAL_CHANNEL, "=== Node %d Neighbor Table ===\n", TOS_NODE_ID);
        if(neighborCount == 0) {
            dbg(GENERAL_CHANNEL, "No neighbors found\n");
        } else {
            for(i = 0; i < neighborCount; i++) {
                dbg(GENERAL_CHANNEL, "Neighbor[%d] = %d\n", i, neighbors[i]);
            }
        }
        dbg(GENERAL_CHANNEL, "=== End Neighbor Table ===\n");
    }

    command uint8_t NeighborDiscovery.getNeighborCount() {
        return neighborCount;
    }

    command uint16_t NeighborDiscovery.getNeighbor(uint8_t neighborIndex) {
        if(neighborIndex < neighborCount) {
            return neighbors[neighborIndex];
        }
        return 0;
    }
}