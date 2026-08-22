#!/bin/tcsh -f
#-------------------------------------------
# qflow exec script for project ~/MyChip_Work/MyChip_Games/dino_run/ETRI050
#-------------------------------------------

# /usr/local/share/qflow/scripts/yosys.sh ~/MyChip_Work/MyChip_Games/dino_run/ETRI050 dino_run ~/MyChip_Work/MyChip_Games/dino_run/ETRI050/source/dino_run.v || exit 1
# /usr/local/share/qflow/scripts/graywolf.sh -d ~/MyChip_Work/MyChip_Games/dino_run/ETRI050 dino_run || exit 1
# /usr/local/share/qflow/scripts/opensta.sh  ~/MyChip_Work/MyChip_Games/dino_run/ETRI050 dino_run || exit 1
# /usr/local/share/qflow/scripts/qrouter.sh ~/MyChip_Work/MyChip_Games/dino_run/ETRI050 dino_run || exit 1
# /usr/local/share/qflow/scripts/opensta.sh  -d ~/MyChip_Work/MyChip_Games/dino_run/ETRI050 dino_run || exit 1
/usr/local/share/qflow/scripts/magic_db.sh ~/MyChip_Work/MyChip_Games/dino_run/ETRI050 dino_run || exit 1
# /usr/local/share/qflow/scripts/magic_drc.sh ~/MyChip_Work/MyChip_Games/dino_run/ETRI050 dino_run || exit 1
# /usr/local/share/qflow/scripts/netgen_lvs.sh ~/MyChip_Work/MyChip_Games/dino_run/ETRI050 dino_run || exit 1
# /usr/local/share/qflow/scripts/magic_gds.sh ~/MyChip_Work/MyChip_Games/dino_run/ETRI050 dino_run || exit 1
# /usr/local/share/qflow/scripts/cleanup.sh ~/MyChip_Work/MyChip_Games/dino_run/ETRI050 dino_run || exit 1
# /usr/local/share/qflow/scripts/cleanup.sh -p ~/MyChip_Work/MyChip_Games/dino_run/ETRI050 dino_run || exit 1
# /usr/local/share/qflow/scripts/magic_view.sh ~/MyChip_Work/MyChip_Games/dino_run/ETRI050 dino_run || exit 1
