#include <Timer.h>
//#include "SimpleSendP.nc"
//#include "../../includes/packet.h"
//#include "../../includes/sendInfo.h"
//#include "../../includes/channels.h"

generic module NeighborDiscoveryP(){
    provides interface NeighborDiscovery;

    uses interface Timer<TMilli> as neighborTimer;
    uses interface Random;

    uses interface Queue<sendInfo*>;
    uses interface Pool<sendInfo>;

    uses interface SimpleSend;
}

implementation {
    command void NeighborDiscovery.findNeighbors(){
        call neighborTimer.startPeriodic(10000+(call Random.rand16()%300));
        
    }

   
    task void search(){
//        "logic: send the message, if there is a response, save the respondent's id inside table"
        call neighborTimer.startPeriodic(100+(call Random.rand16()%300));
    }

    event void neighborTimer.fired(){
        pack message;
        uint16_t destination = AM_BROADCAST_ADDR;
        call SimpleSend.send(message, destination);
//        call neighborTimer.startOneShot(100000);
    }

    command void NeighborDiscovery.neighborUpdate(){
        dbg(NEIGHBOR_CHANNEL, "Neighbor Update Event Triggered\n");
    }
/*
    event void neighborTimer.fired(){
        uint8_t *payload;
        dbg(NEIGHBOR_CHANNEL, "NEIGHBOR DISCOVERY TEST EVENT \n");
        makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, 0, 0, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
        call Sender.send(sendPackage, destination);
    }*/

    command void NeighborDiscovery.printNeighbors(){
        dbg(NEIGHBOR_CHANNEL,"This is a neighbordiscovery test\n");
    };
}