#include "../../includes/am_types.h"

//generic configuration NeighborDiscoveryC(int channel){
configuration NeighborDiscoveryC{

    provides interface NeighborDiscovery;
}

implementation{
    components new NeighborDiscoveryP();
    NeighborDiscovery = NeighborDiscoveryP.NeighborDiscovery;

//    components new Timer MilliC() as neighborTimer;
//    NeighborDiscoveryP.neighborTimer -> neighborTimer;

//    components RandomC as Random;
//    NeighborDiscoveryP.Random -> Random;
}