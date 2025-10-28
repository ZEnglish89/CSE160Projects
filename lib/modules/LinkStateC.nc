#include "../../includes/CommandMsg.h"
#include "../../includes/command.h"
#include "../../includes/channels.h"

configuration LinkStateC{
    provides interface LinkState;
    uses interface NeighborDiscovery;
}

implementation{
    components LinkStateP;
    LinkState = LinkStateP.LinkState;

    components new SimpleSendC(AM_PACK);
    LinkStateP.SimpleSend -> SimpleSendC;

    LinkStateP.NeighborDiscovery -> NeighborDiscovery;

    components FloodingC;
    LinkStateP.Flooding -> FloodingC;
    
    components new TimerMilliC() as LsTimer;
    LinkStateP.LsTimer -> LsTimer;
}