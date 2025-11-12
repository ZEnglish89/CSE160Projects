//basing this one on IPC.nc, it will change as the implementation takes shape
#include "../../includes/CommandMsg.h"
#include "../../includes/command.h"
#include "../../includes/channels.h"

configuration TCPC{
    provides interface TCP;
}

implementation{
//we will definitely need IP, I'm not sure what else as the moment but we can add as we go.

    components TCPP;
    TCP = TCPP.TCP;

    components IPC;
    TCPP.IP -> IPC;

/*
    components new SimpleSendC(AM_PACK);
    IPP.SimpleSend -> SimpleSendC;

    components LinkStateC;
    IPP.LinkState -> LinkStateC;

//I'm including Flooding so that if we receive a packet that should be broadcast,
//we can flood it.
    components FloodingC;
    IPP.Flooding -> FloodingC;
*/
}