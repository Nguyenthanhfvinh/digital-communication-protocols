# ==================== CONFIG ====================
SHELL         := /bin/bash
.DEFAULT_GOAL := help
.DELETE_ON_ERROR:

# Testbench top
TB_NAME       ?= tb_i2c_master

# Danh sách source
SRC_LIST      ?= compile.f

# Log và waveform
LOG_DIR       ?= ./log
LOG_FILE      ?= $(LOG_DIR)/tb.log
WLF_FILE      ?= $(LOG_DIR)/tb.wlf
SIM_LOG_LINK  ?= ./sim.log

# Coverage
COVERAGE      ?= 0
COV_DIR       ?= ./cov
UCDB_FILE     ?= $(COV_DIR)/coverage.ucdb
COV_TEXT_FILE ?= $(COV_DIR)/coverage.txt
COV_HTML_DIR  ?= $(COV_DIR)/html

# b = branch
# c = condition
# e = expression
# f = FSM
# s = statement
# t = toggle
COV_CODE      ?= bcefst

# QuestaSim options
RADIX           ?= hexadecimal
VLOG_OPTS       ?= -sv +define+SIM
VSIM_OPTS       ?= -voptargs=+acc -assertdebug
VCOVER_OPTS     ?= -details -code $(COV_CODE)

EXTRA_VLOG_OPTS ?=
EXTRA_VSIM_OPTS ?=

# Chỉ bật instrumentation khi COVERAGE=1
ifeq ($(COVERAGE),1)
  VLOG_COV_OPTS := +cover=$(COV_CODE)
  VSIM_COV_OPTS := -coverage
else
  VLOG_COV_OPTS :=
  VSIM_COV_OPTS :=
endif

# ==================== PHONY ====================
.PHONY: help all compile run debug wave openwave \
        cov cov-report cov-open cov-gui \
        check report openlog rebuild \
        clean distclean realclean

# ==================== HELP ====================
help:
	@printf '%s\n' ""
	@printf '%s\n' "╔══════════════════════════════════════════════════════════════════════════════╗"
	@printf '%s\n' "║                 UART VERIFICATION - QUESTA/MODELSIM MAKEFILE                 ║"
	@printf '%s\n' "╠══════════════════════════════════════════════════════════════════════════════╣"
	@printf '%s\n' "║  make compile     Compile source                                             ║"
	@printf '%s\n' "║  make run         Compile + chạy simulation batch                            ║"
	@printf '%s\n' "║  make debug       Compile + mở GUI                                           ║"
	@printf '%s\n' "║  make wave        Mở các tín hiệu top-level của testbench                    ║"
	@printf '%s\n' "║  make check       Chạy simulation và kiểm tra PASS/FAIL                      ║"
	@printf '%s\n' "║                                                                              ║"
	@printf '%s\n' "║  make cov         Chạy coverage và tạo UCDB + text + HTML                    ║"
	@printf '%s\n' "║  make cov-report  Xem coverage dạng text                                     ║"
	@printf '%s\n' "║  make cov-open    Mở HTML coverage bằng trình duyệt                          ║"
	@printf '%s\n' "║  make cov-gui     Mở coverage database trong QuestaSim                       ║"
	@printf '%s\n' "║                                                                              ║"
	@printf '%s\n' "║  make report      Xem 40 dòng cuối của simulation log                        ║"
	@printf '%s\n' "║  make openlog     Mở toàn bộ simulation log                                  ║"
	@printf '%s\n' "║  make rebuild     Xóa file cũ rồi compile và chạy lại                        ║"
	@printf '%s\n' "║  make clean       Xóa toàn bộ file sinh ra                                   ║"
	@printf '%s\n' "╠══════════════════════════════════════════════════════════════════════════════╣"
	@printf '%s\n' "║  COVERAGE OUTPUT                                                             ║"
	@printf '║    %-74s║\n' "UCDB : $(UCDB_FILE)"
	@printf '║    %-74s║\n' "Text : $(COV_TEXT_FILE)"
	@printf '║    %-74s║\n' "HTML : $(COV_HTML_DIR)/index.html"
	@printf '%s\n' "╠══════════════════════════════════════════════════════════════════════════════╣"
	@printf '%s\n' "║  Ví dụ                                                                       ║"
	@printf '║    %-74s║\n' "make clean && make cov"
	@printf '║    %-74s║\n' "make cov-open"
	@printf '║    %-74s║\n' "make run TB_NAME=$(TB_NAME)"
	@printf '║    %-74s║\n' 'make cov EXTRA_VLOG_OPTS="+define+TEST_CASE=ALL"'
	@printf '%s\n' "╚══════════════════════════════════════════════════════════════════════════════╝"
	@printf '%s\n' ""
# ==================== COMPILE ====================
compile:
	@echo "════════════════════════════════════════════════════════════════════════════"
	@echo " [COMPILE] TB             = $(TB_NAME)"
	@echo " [COMPILE] SOURCE LIST    = $(SRC_LIST)"
	@echo " [COMPILE] COVERAGE       = $(COVERAGE)"
	@echo " [COMPILE] VLOG COVER OPT = $(VLOG_COV_OPTS)"
	@echo "════════════════════════════════════════════════════════════════════════════"
	@if [ ! -f "$(SRC_LIST)" ]; then \
		echo "[ERROR] Không tìm thấy file $(SRC_LIST)"; \
		echo "        Hãy tạo compile.f và thêm các file .v/.sv vào đó."; \
		exit 1; \
	fi
	@rm -rf work
	vlib work
	vmap work work
	vlog $(VLOG_OPTS) $(VLOG_COV_OPTS) $(EXTRA_VLOG_OPTS) -f "$(SRC_LIST)"
	@echo "[OK] Compile thành công"

# ==================== RUN BATCH ====================
run: compile
	@mkdir -p "$(LOG_DIR)"
	@if [ "$(COVERAGE)" = "1" ]; then \
		mkdir -p "$(COV_DIR)"; \
		rm -f "$(UCDB_FILE)" "$(COV_TEXT_FILE)"; \
		rm -rf "$(COV_HTML_DIR)"; \
	fi
	@echo "════════════════════════════════════════════════════════════════════════════"
	@echo " [RUN] TB       = $(TB_NAME)"
	@echo " [RUN] LOG      = $(LOG_FILE)"
	@echo " [RUN] WAVE     = $(WLF_FILE)"
	@echo " [RUN] COVERAGE = $(COVERAGE)"
	@if [ "$(COVERAGE)" = "1" ]; then \
		echo " [RUN] UCDB     = $(UCDB_FILE)"; \
	fi
	@echo "════════════════════════════════════════════════════════════════════════════"
	@start=$$(date +%s); \
	if [ "$(COVERAGE)" = "1" ]; then \
		do_cmd="coverage save -onexit $(UCDB_FILE); log -r /*; run -all; quit -f;"; \
	else \
		do_cmd="log -r /*; run -all; quit -f;"; \
	fi; \
	vsim \
		-l "$(LOG_FILE)" \
		-wlf "$(WLF_FILE)" \
		$(VSIM_OPTS) \
		$(VSIM_COV_OPTS) \
		$(EXTRA_VSIM_OPTS) \
		-c "$(TB_NAME)" \
		-do "$$do_cmd"; \
	sim_status=$$?; \
	end=$$(date +%s); \
	elapsed=$$((end - start)); \
	echo "" | tee -a "$(LOG_FILE)"; \
	echo "════════════════════════════════════════════════════════════════" | tee -a "$(LOG_FILE)"; \
	echo " Elapsed time: $${elapsed} seconds" | tee -a "$(LOG_FILE)"; \
	if [ $$sim_status -eq 0 ]; then \
		echo " [DONE] Simulation finished normally" | tee -a "$(LOG_FILE)"; \
	else \
		echo " [FAIL] vsim exited with code $$sim_status" | tee -a "$(LOG_FILE)"; \
	fi; \
	echo "════════════════════════════════════════════════════════════════" | tee -a "$(LOG_FILE)"; \
	ln -sf "$(LOG_FILE)" "$(SIM_LOG_LINK)" 2>/dev/null || true; \
	echo "[DONE] Log  -> $(LOG_FILE)"; \
	echo "[DONE] Wave -> $(WLF_FILE)"; \
	if [ $$sim_status -eq 0 ] && [ "$(COVERAGE)" = "1" ]; then \
		if [ ! -f "$(UCDB_FILE)" ]; then \
			echo "[ERROR] QuestaSim không tạo file UCDB: $(UCDB_FILE)"; \
			echo "        Kiểm tra log: $(LOG_FILE)"; \
			sim_status=2; \
		else \
			echo "[COVERAGE] Đang tạo báo cáo text..."; \
			vcover report \
				$(VCOVER_OPTS) \
				"$(UCDB_FILE)" \
				> "$(COV_TEXT_FILE)"; \
			text_status=$$?; \
			echo "[COVERAGE] Đang tạo báo cáo HTML..."; \
			vcover report \
				-html \
				-output "$(COV_HTML_DIR)" \
				$(VCOVER_OPTS) \
				"$(UCDB_FILE)"; \
			html_status=$$?; \
			if [ $$text_status -ne 0 ] || [ $$html_status -ne 0 ]; then \
				echo "[ERROR] Không thể tạo đầy đủ coverage report"; \
				sim_status=3; \
			else \
				echo "════════════════════════════════════════════════════════════════"; \
				echo "[DONE] Coverage database -> $(UCDB_FILE)"; \
				echo "[DONE] Coverage text     -> $(COV_TEXT_FILE)"; \
				echo "[DONE] Coverage HTML     -> $(COV_HTML_DIR)/index.html"; \
				echo "════════════════════════════════════════════════════════════════"; \
			fi; \
		fi; \
	fi; \
	exit $$sim_status

# ==================== COVERAGE ====================
cov:
	@$(MAKE) run COVERAGE=1

cov-report:
	@if [ ! -f "$(COV_TEXT_FILE)" ]; then \
		echo "[ERROR] Không tìm thấy $(COV_TEXT_FILE)"; \
		echo "        Hãy chạy: make cov"; \
		exit 1; \
	fi
	less -R "$(COV_TEXT_FILE)"

cov-open:
	@if [ ! -f "$(COV_HTML_DIR)/index.html" ]; then \
		echo "[ERROR] Không tìm thấy $(COV_HTML_DIR)/index.html"; \
		echo "        Hãy chạy: make cov"; \
		exit 1; \
	fi
	@echo "[OPEN] $(COV_HTML_DIR)/index.html"
	xdg-open "$(COV_HTML_DIR)/index.html" >/dev/null 2>&1 &

cov-gui:
	@if [ ! -f "$(UCDB_FILE)" ]; then \
		echo "[ERROR] Không tìm thấy $(UCDB_FILE)"; \
		echo "        Hãy chạy: make cov"; \
		exit 1; \
	fi
	vsim -viewcov "$(UCDB_FILE)"

# ==================== DEBUG GUI ====================
debug: compile
	@mkdir -p "$(LOG_DIR)"
	@if [ "$(COVERAGE)" = "1" ]; then \
		mkdir -p "$(COV_DIR)"; \
	fi
	@echo "════════════════════════════════════════════════════════════════════════════"
	@echo " [DEBUG] Launching QuestaSim GUI: $(TB_NAME)"
	@echo " [DEBUG] COVERAGE = $(COVERAGE)"
	@echo "════════════════════════════════════════════════════════════════════════════"
	@if [ "$(COVERAGE)" = "1" ]; then \
		cov_cmd="coverage save -onexit $(UCDB_FILE);"; \
	else \
		cov_cmd=""; \
	fi; \
	vsim \
		-i \
		$(VSIM_OPTS) \
		$(VSIM_COV_OPTS) \
		$(EXTRA_VSIM_OPTS) \
		"$(TB_NAME)" \
		-do "$$cov_cmd \
		     log -r /*; \
		     add wave -r /$(TB_NAME)/*; \
		     configure wave -signalnamewidth 1; \
		     radix -$(RADIX); \
		     run -all;"

# ==================== WAVEFORM ====================
wave openwave:
	@if [ ! -f "$(WLF_FILE)" ]; then \
		echo "[ERROR] Không tìm thấy $(WLF_FILE)"; \
		echo "        Hãy chạy: make run hoặc make cov"; \
		exit 1; \
	fi
	@echo "[WAVE] Opening $(WLF_FILE)"
	vsim \
		-i \
		-view "$(WLF_FILE)" \
		-do "view wave; \
		     add wave /$(TB_NAME)/*; \
		     configure wave -signalnamewidth 1; \
		     radix -$(RADIX); \
		     wave zoom full;"

# ==================== CHECK PASS/FAIL ====================
check: run
	@echo ""
	@echo "════════════════════════════════════════════════════════════════════════════"
	@echo " [CHECK] Analyzing $(LOG_FILE)"
	@echo "════════════════════════════════════════════════════════════════════════════"
	@if [ ! -f "$(LOG_FILE)" ]; then \
		echo "[ERROR] Không tìm thấy simulation log"; \
		exit 1; \
	fi
	@errors=$$(grep -cE "# \*\* Error|# Error|Error:|FATAL|UVM_ERROR|UVM_FATAL" "$(LOG_FILE)" || true); \
	fails=$$(grep -cE "TEST FAILED|FAILED|Assertion.*failed" "$(LOG_FILE)" || true); \
	passes=$$(grep -cE "TEST PASSED|PASSED|Simulation PASSED|# \*\* Note:.*PASS" "$(LOG_FILE)" || true); \
	if [ $$errors -gt 0 ] || [ $$fails -gt 0 ]; then \
		echo "[RESULT] FAIL"; \
		echo "         Errors        : $$errors"; \
		echo "         Explicit FAIL : $$fails"; \
		echo "         Xem log bằng  : make openlog"; \
		exit 1; \
	elif [ $$passes -gt 0 ]; then \
		echo "[RESULT] PASS"; \
	else \
		echo "[RESULT] UNKNOWN"; \
		echo "         Không tìm thấy từ khóa PASS/FAIL rõ ràng."; \
	fi

# ==================== REPORT ====================
report:
	@echo "=== LAST SIMULATION RESULT ==="
	@if [ -f "$(LOG_FILE)" ]; then \
		echo "Log: $(LOG_FILE)"; \
		echo "----------------------------------------"; \
		tail -n 40 "$(LOG_FILE)"; \
	else \
		echo "[ERROR] Không tìm thấy log."; \
		echo "        Hãy chạy: make run"; \
	fi

# ==================== OPEN LOG ====================
openlog:
	@if [ -f "$(LOG_FILE)" ]; then \
		less -R "$(LOG_FILE)"; \
	elif [ -f "$(SIM_LOG_LINK)" ]; then \
		less -R "$(SIM_LOG_LINK)"; \
	else \
		echo "[ERROR] Không có simulation log để mở"; \
	fi

# ==================== REBUILD ====================
rebuild: clean run

# ==================== CLEAN ====================
clean:
	@echo "[CLEAN] Removing simulation and coverage artifacts..."
	@rm -rf work
	@rm -rf "$(LOG_DIR)"
	@rm -rf "$(COV_DIR)"
	@rm -rf covhtmlreport
	@rm -f *.ucdb
	@rm -f modelsim.ini
	@rm -f transcript
	@rm -f vsim.wlf
	@rm -f *.wlf
	@rm -f *.log
	@rm -f sim.log
	@rm -f wlft*
	@rm -f vish_stacktrace.vstf
	@rm -f *.vstf
	@rm -f *.bak
	@rm -f *~
	@rm -f .*.swp
	@rm -f .*.swo
	@rm -rf .vsim*
	@echo "[CLEAN] Done"

distclean: clean
	@echo "[DISTCLEAN] Removing extra generated files..."
	@rm -f regress.list
	@rm -f run_test.vt
	@rm -f *.do~
	@rm -f compile.f.bak
	@rm -rf simv*
	@rm -rf csrc
	@rm -rf DVEfiles
	@echo "[DISTCLEAN] Done"

realclean: distclean
	@rm -rf *.tmp
	@rm -rf *.temp
	@rm -f .Makefile.swp
	@echo "[REALCLEAN] Done"

# ==================== ALL ====================
all: run