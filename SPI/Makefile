##################################################################################################
# This file created by Huy Nguyen
# Fixed for Ubuntu/Linux + full_adder
# Run:
#   make all
#   make wave
#   make clean
##################################################################################################

.RECIPEPREFIX := >

# Define variables
TESTNAME        ?= master_spi
TB_NAME         ?= tb_master
RADIX           ?= hexadecimal
REGRESS_LIST    ?= regress.list
SRCLIST_V_T     ?= compile
COV_NAME        ?= coverage
COV_DB          ?= $(COV_NAME).ucdb
COV_DIR         ?= coverage

macro_en        ?=

# Questa / ModelSim tools for Linux
VLIB            ?= vlib
VMAP            ?= vmap
VLOG            ?= vlog
VSIM            ?= vsim
VCOVER          ?= vcover

#================================================================================================
.PHONY: all regression regression_cov build run cov cov_compile cov_run cov_report \
        find create_test_list regress regress_cov wave run_cov gen_cov clean report

# Run code coverage with one command: make cov
cov: cov_compile cov_run cov_report

cov_compile:
>rm -rf work $(COV_DB) covhtmlreport
>mkdir -p $(COV_DIR)
>$(VLIB) work
>$(VMAP) work work
>$(VLOG) -coveropt 3 +cover +acc -f $(SRCLIST_V_T).f

cov_run:
>$(VSIM) -coverage -vopt work.$(TB_NAME) -c -wlf log/$(TESTNAME)_cov.wlf -do "coverage save -onexit -directive -codeAll $(COV_DB); log -r /$(TB_NAME)/*; run -all; quit -f"

cov_report:
>$(VCOVER) report -html $(COV_DB)
>rm -rf $(COV_DIR)/html
>mv covhtmlreport $(COV_DIR)/html
>$(VCOVER) report $(COV_DB) -file $(COV_DIR)/summary_report.txt
>@echo "Coverage database: $(COV_DB)"
>@echo "HTML report: $(COV_DIR)/html/index.html"
>@echo "Text report: $(COV_DIR)/summary_report.txt"

all: build run

regression: build create_test_list regress report

regression_cov: build create_test_list regress_cov gen_cov

build:
>mkdir -p log
>touch run_test.vt
>rm -rf work
>$(VLIB) work
>$(VMAP) work work
>$(VLOG) $(macro_en) -coveropt 3 +cover +acc -f $(SRCLIST_V_T).f

run:
>$(VSIM) -l log/$(TESTNAME).log -voptargs=+acc -assertdebug -c work.$(TB_NAME) -wlf log/$(TESTNAME).wlf -do "log -r /$(TB_NAME)/*; run -all; quit -f"
>ln -sf log/$(TESTNAME).log sim.log

find:
>find tb

create_test_list:
>find tb -type f -printf "%f\n" | sed 's/.vt//' | tee $(REGRESS_LIST) | wc -l

regress:
>./run_all.sh run

regress_cov:
>./run_all.sh run_cov

wave:
>$(VSIM) -i -view log/$(TESTNAME).wlf -do "add wave -r /$(TB_NAME)/*; radix -$(RADIX)"

run_cov:
>mkdir -p log
>cp -rf tb/$(TESTNAME).vt run_test.vt
>$(VLOG) +cover=sbceftx -f compile.f
>$(VSIM) -coverage -l log/$(TESTNAME).log -c work.$(TB_NAME) -wlf log/$(TESTNAME).wlf -voptargs="+cover=bcesfx" -assertdebug -do "coverage save -onexit $(TESTNAME).ucdb; log -r /$(TB_NAME)/*; run -all; quit -f"

gen_cov:
>mkdir -p coverage
>$(VCOVER) merge IP.ucdb *.ucdb
>$(VCOVER) report IP.ucdb -file coverage/summary_report.txt
>$(VCOVER) report -zeros -details -code bcefsx -All -codeAll IP.ucdb -file coverage/detail_report.txt

clean:
>rm -rf work
>rm -rf log
>rm -rf *.ini
>rm -rf *.log
>rm -rf *.wlf
>rm -rf transcript
>rm -rf coverage
>rm -rf *.ucdb
>rm -rf *.list
>rm -rf *.vt
>rm -rf covhtmlreport
>rm -rf sim.log

report:
>grep "passed" ./log/*.log -R || true
