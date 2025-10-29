#include "../../includes/am_types.h"
#include "../../includes/packet.h"
#include <Timer.h>

configuration NeighborDiscoveryC{

    provides interface NeighborDiscovery;
}

implementation{
    components NeighborDiscoveryP;
    NeighborDiscovery = NeighborDiscoveryP.NeighborDiscovery;

    components new TimerMilliC() as neighborTimer;
    NeighborDiscoveryP.neighborTimer -> neighborTimer;

    components RandomC as Random;
    NeighborDiscoveryP.Random -> Random;

    components new SimpleSendC(AM_PACK);
    NeighborDiscoveryP.SimpleSend -> SimpleSendC;
}