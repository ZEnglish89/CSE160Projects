#include "../../includes/CommandMsg.h"
#include "../../includes/command.h"
#include "../../includes/channels.h"

configuration TCPC {
    provides interface TCP;
}

implementation {
    components TCPP;
    TCP = TCPP.TCP;

    components IPC;
    TCPP.IP -> IPC;
    
    components new TimerMilliC() as RetransmitTimer;
    TCPP.RetransmitTimer -> RetransmitTimer;

    components NeighborDiscoveryC;
    TCPP.NeighborDiscovery -> NeighborDiscoveryC; 
}