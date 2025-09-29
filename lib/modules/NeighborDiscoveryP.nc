#include <Timer.h>

generic module NeighborDiscoveryP(){
    provides interface NeighborDiscovery;

//    uses interface Timer<TMilli> as neighborTimer;
//    uses interface Random;
}

implementation {
    command void NeighborDiscovery.findNeighbors(){
//        call neighborTimer.startOneShot(100+(call Random.rand16()%300));
    }

//    task void search(){
//        "logic: send the message, if there is a response, save the respondent's id inside table"
//        call neighborTimer.startPeriodic(100+(call Random.rand16()%300));
//    }

//    event void neighborTimer.fired(){
//        post sendBufferTask();
//    }

    command void NeighborDiscovery.printNeighbors(){
        dbg(NEIGHBOR_CHANNEL,"This is a neighbordiscovery test\n");
    };
}