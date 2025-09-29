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
        call neighborTimer.startOneShot(100+(call Random.rand16()%300));
    }

   
    task void search(){
//        "logic: send the message, if there is a response, save the respondent's id inside table"
        call neighborTimer.startPeriodic(100+(call Random.rand16()%300));
    }
/*
    event void neighborTimer.fired(){
        pack message;
        uint16_t destination = AM_BROADCAST_ADDR;
        call SimpleSend.send(message, destination);
    }*/

    event void neighborTimer.fired(){
        pack message;
        call SimpleSend.send(message, AM_BROADCAST_ADDR);

    }

    command void NeighborDiscovery.printNeighbors(){};
}