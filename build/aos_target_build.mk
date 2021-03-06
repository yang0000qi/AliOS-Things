include $(MAKEFILES_PATH)/aos_host_cmd.mk

CONFIG_FILE := $(OUTPUT_DIR)/config.mk

include $(CONFIG_FILE)

# Include all toolchain makefiles - one of them will handle the architecture
include $(MAKEFILES_PATH)/aos_toolchain_gcc.mk

.PHONY: display_map_summary build_done

##################################
# Filenames
##################################

LINK_OUTPUT_FILE          :=$(OUTPUT_DIR)/binary/$(CLEANED_BUILD_STRING)$(RADIXPOINT)$(BINSTYPE_LOWER)$(LINK_OUTPUT_SUFFIX)        	# out/helloworld@mk108/binary/helloworld@mk108.elf
STRIPPED_LINK_OUTPUT_FILE :=$(LINK_OUTPUT_FILE:$(LINK_OUTPUT_SUFFIX)=.stripped$(LINK_OUTPUT_SUFFIX)) 	# out/helloworld@mk108/binary/helloworld@mk108.stripped.elf
BIN_OUTPUT_FILE           :=$(LINK_OUTPUT_FILE:$(LINK_OUTPUT_SUFFIX)=$(BIN_OUTPUT_SUFFIX))         		# out/helloworld@mk108/binary/helloworld@mk108.bin
HEX_OUTPUT_FILE           :=$(LINK_OUTPUT_FILE:$(LINK_OUTPUT_SUFFIX)=$(HEX_OUTPUT_SUFFIX))         		# out/helloworld@mk108/binary/helloworld@mk108.bin

MAP_OUTPUT_FILE           :=$(LINK_OUTPUT_FILE:$(LINK_OUTPUT_SUFFIX)=.map)     							# out/helloworld@mk108/binary/helloworld@mk108.map
MAP_CSV_OUTPUT_FILE       :=$(LINK_OUTPUT_FILE:$(LINK_OUTPUT_SUFFIX)=_map.csv) 							# out/helloworld@mk108/binary/helloworld@mk108_map.csv


OPENOCD_LOG_FILE          ?= $(OUTPUT_DIR)/openocd_log.txt

LIBS_DIR                  := $(OUTPUT_DIR)/libraries
LINK_OPTS_FILE            := $(OUTPUT_DIR)/binary/link$(UNDERLINE)$(BINSTYPE_LOWER).opts

LINT_OPTS_FILE            := $(OUTPUT_DIR)/binary/lint$(UNDERLINE)$(BINSTYPE_LOWER).opts

LDS_FILE_DIR              := $(OUTPUT_DIR)/ld

ifeq (,$(SUB_BUILD))
ifneq (,$(EXTRA_TARGET_MAKEFILES))
$(foreach makefile_name,$(EXTRA_TARGET_MAKEFILES),$(eval include $(makefile_name)))
endif
endif


include $(MAKEFILES_PATH)/aos_resources.mk
include $(MAKEFILES_PATH)/aos_images_download.mk

##################################
# Macros
##################################

###############################################################################
# MACRO: GET_BARE_LOCATION
# Returns a the location of the given component relative to source-tree-root
# rather than from the cwd
# $(1) is component
GET_BARE_LOCATION =$(patsubst $(call ESCAPE_BACKSLASHES,$(SOURCE_ROOT))%,%,$(strip $(subst :,/,$($(1)_LOCATION))))


###############################################################################
# MACRO: BUILD_C_RULE
# Creates a target for building C language files (*.c)
# $(1) is component, $(2) is the source file
define BUILD_C_RULE
-include $(OUTPUT_DIR)/Modules/$(call GET_BARE_LOCATION,$(1))$(2:.c=.d)
$(OUTPUT_DIR)/Modules/$(call GET_BARE_LOCATION,$(1))$(2:.c=.o): $(strip $($(1)_LOCATION))$(2) $(CONFIG_FILE) $$(dir $(OUTPUT_DIR)/Modules/$(call GET_BARE_LOCATION,$(1))$(2)).d $(RESOURCES_DEPENDENCY) $(LIBS_DIR)/$(1).c_opts | $(EXTRA_PRE_BUILD_TARGETS)
	$$(if $($(1)_START_PRINT),,$(eval $(1)_START_PRINT:=1) $(QUIET)$(ECHO) Compiling $(1) )
	$(QUIET)$(CC) $(OPTIONS_IN_FILE_OPTION)$(LIBS_DIR)/$(1).c_opts -D__FILENAME__='"$$(notdir $$<)"' -o $$@ $$< $(COMPILER_SPECIFIC_STDOUT_REDIRECT)
endef

###############################################################################
# MACRO: CHECK_HEADER_RULE
# Compiles a C language header file to ensure it is stand alone complete
# $(1) is component, $(2) is the source header file
define CHECK_HEADER_RULE
$(eval $(1)_CHECK_HEADER_LIST+=$(OUTPUT_DIR)/Modules/$(strip $($(1)_LOCATION))$(2:.h=.chk) )
.PHONY: $(OUTPUT_DIR)/Modules/$(strip $($(1)_LOCATION))$(2:.h=.chk)
$(OUTPUT_DIR)/Modules/$(strip $($(1)_LOCATION))$(2:.h=.chk): $(strip $($(1)_LOCATION))$(2) $(CONFIG_FILE) $$(dir $(OUTPUT_DIR)/Modules/$(call GET_BARE_LOCATION,$(1))$(2)).d
	$(QUIET)$(ECHO) Checking header  $(2)
	$(QUIET)$(CC) -c $(AOS_SDK_CFLAGS) $(filter-out -pedantic -Werror, $($(1)_CFLAGS) $(C_BUILD_OPTIONS) ) $($(1)_INCLUDES) $($(1)_DEFINES) $(AOS_SDK_INCLUDES) $(AOS_SDK_DEFINES) -o $$@ $$<
endef

###############################################################################
# MACRO: BUILD_CPP_RULE
# Creates a target for building C++ language files (*.cpp)
# $(1) is component name, $(2) is the source file
define BUILD_CPP_RULE
-include $(OUTPUT_DIR)/Modules/$(call GET_BARE_LOCATION,$(1))$(patsubst %.cc,%.d,$(2:.cpp=.d))
$(OUTPUT_DIR)/Modules/$(call GET_BARE_LOCATION,$(1))$(patsubst %.cc,%.o,$(2:.cpp=.o)): $(strip $($(1)_LOCATION))$(2) $(CONFIG_FILE) $$(dir $(OUTPUT_DIR)/Modules/$(call GET_BARE_LOCATION,$(1))$(2)).d $(RESOURCES_DEPENDENCY) $(LIBS_DIR)/$(1).cpp_opts | $(EXTRA_PRE_BUILD_TARGETS)
	$$(if $($(1)_START_PRINT),,$(eval $(1)_START_PRINT:=1) $(ECHO) Compiling $(1))
	$(QUIET)$(CXX) $(OPTIONS_IN_FILE_OPTION)$(LIBS_DIR)/$(1).cpp_opts -o $$@ $$<  $(COMPILER_SPECIFIC_STDOUT_REDIRECT)
endef

###############################################################################
# MACRO: BUILD_S_RULE
# Creates a target for building Assembly language files (*.s & *.S)
# $(1) is component name, $(2) is the source file
define BUILD_S_RULE
$(OUTPUT_DIR)/Modules/$(call GET_BARE_LOCATION,$(1))$(strip $(patsubst %.S,%.o, $(2:.s=.o) )): $(strip $($(1)_LOCATION))$(2) $($(1)_PRE_BUILD_TARGETS) $(CONFIG_FILE) $$(dir $(OUTPUT_DIR)/Modules/$(call GET_BARE_LOCATION,$(1))$(strip $(patsubst %.S, %.o, $(2)))).d $(RESOURCES_DEPENDENCY) $(LIBS_DIR)/$(1).c_opts | $(EXTRA_PRE_BUILD_TARGETS)
	$$(if $($(1)_START_PRINT),,$(eval $(1)_START_PRINT:=1) $(ECHO) Compiling $(1))
	$(QUIET)$(CC) $(OPTIONS_IN_FILE_OPTION)$(LIBS_DIR)/$(1).c_opts -o $$@ $$< $(COMPILER_SPECIFIC_STDOUT_REDIRECT)
endef

###############################################################################
# MACRO: BUILD_COMPONENT_RULES
# Creates targets for building an entire component
# Target for the component static library is created in this macro
# Targets for source files are created by calling the macros defined above
# $(1) is component name
define BUILD_COMPONENT_RULES

$(eval LINK_LIBS +=$(if $($(1)_SOURCES),$(LIBS_DIR)/$(1).a))


ifneq ($($(1)_PRE_BUILD_TARGETS),)
include $($(1)_MAKEFILE)
endif

# Make a list of the object files that will be used to build the static library
$(eval $(1)_LIB_OBJS := $(addprefix $(strip $(OUTPUT_DIR)/Modules/$(call GET_BARE_LOCATION,$(1))),  $(filter %.o, $($(1)_SOURCES:.cc=.o) $($(1)_SOURCES:.cpp=.o) $($(1)_SOURCES:.c=.o) $($(1)_SOURCES:.s=.o) $($(1)_SOURCES:.S=.o)))  $(patsubst %.c,%.o,$(call RESOURCE_FILENAME, $($(1)_RESOURCES))))


$(LIBS_DIR)/$(1).c_opts: $($(1)_PRE_BUILD_TARGETS) $(CONFIG_FILE) | $(LIBS_DIR)
	$(QUIET)$$(call WRITE_FILE_CREATE, $$@, $(subst $(COMMA),$$(COMMA), $(COMPILER_SPECIFIC_COMP_ONLY_FLAG) $(COMPILER_SPECIFIC_DEPS_FLAG) $($(1)_CFLAGS) $($(1)_INCLUDES) $($(1)_DEFINES) $(AOS_SDK_INCLUDES) $(AOS_SDK_DEFINES)))

$(LIBS_DIR)/$(1).cpp_opts: $($(1)_PRE_BUILD_TARGETS) $(CONFIG_FILE) | $(LIBS_DIR)
	 $(QUIET)$$(call WRITE_FILE_CREATE, $$@ ,$(COMPILER_SPECIFIC_COMP_ONLY_FLAG) $(COMPILER_SPECIFIC_DEPS_FLAG) $($(1)_CXXFLAGS)  $($(1)_INCLUDES) $($(1)_DEFINES) $(AOS_SDK_INCLUDES) $(AOS_SDK_DEFINES))

#$(LIBS_DIR)/$(1).as_opts: $(CONFIG_FILE) | $(LIBS_DIR)
#	$(QUIET)$$(call WRITE_FILE_CREATE, $$@ ,$($(1)_ASMFLAGS))

$(LIBS_DIR)/$(1).ar_opts: $(CONFIG_FILE) | $(LIBS_DIR)
	$(QUIET)$$(call WRITE_FILE_CREATE, $$@ ,$($(1)_LIB_OBJS))

# Allow checking of completeness of headers
$(foreach src, $(if $(findstring 1,$(CHECK_HEADERS)), $(filter %.h, $($(1)_CHECK_HEADERS)), ),$(eval $(call CHECK_HEADER_RULE,$(1),$(src))))

# Target for build-from-source
#$(OUTPUT_DIR)/libraries/$(1).a: $$($(1)_LIB_OBJS) $($(1)_CHECK_HEADER_LIST) $(OUTPUT_DIR)/libraries/$(1).ar_opts $$(if $(AOS_BUILT_WITH_ROM_SYMBOLS),$(ROMOBJCOPY_OPTS_FILE))
$(LIBS_DIR)/$(1).a: $$($(1)_LIB_OBJS) $($(1)_CHECK_HEADER_LIST) $(OUTPUT_DIR)/libraries/$(1).ar_opts
	$(ECHO) Making $$@
	$(QUIET)$(AR) $(AOS_SDK_ARFLAGS) $(COMPILER_SPECIFIC_ARFLAGS_CREATE) $$@ $(OPTIONS_IN_FILE_OPTION)$(OUTPUT_DIR)/libraries/$(1).ar_opts

# Create targets to built the component's source files into object files
$(foreach src, $(filter %.c, $($(1)_SOURCES)),$(eval $(call BUILD_C_RULE,$(1),$(src))))
$(foreach src, $(filter %.cpp, $($(1)_SOURCES)) $(filter %.cc, $($(1)_SOURCES)),$(eval $(call BUILD_CPP_RULE,$(1),$(src))))
$(foreach src, $(filter %.s %.S, $($(1)_SOURCES)),$(eval $(call BUILD_S_RULE,$(1),$(src))))


$(eval $(1)_LINT_FLAGS +=  $(filter -D% -I%, $($(1)_CFLAGS) $($(1)_INCLUDES) $($(1)_DEFINES) $(AOS_SDK_INCLUDES) $(AOS_SDK_DEFINES) ) )
$(eval LINT_FLAGS +=  $($(1)_LINT_FLAGS) )
$(eval LINT_FILES +=  $(addprefix $(strip $($(1)_LOCATION)), $(filter %.c, $($(1)_SOURCES))) )
endef

define PROCESS_LDS_FILE
$(LDS_FILE_DIR)/$(notdir $(1:.ld.S=.ld)): $(LDS_FILE_DIR)
	$(ECHO) Making $$@
	$(QUIET)$(CPP) -P $(AOS_SDK_CFLAGS) $(AOS_SDK_INCLUDES) $(AOS_SDK_DEFINES) $(1) -o $$@

$(eval LDS_FILES += $(LDS_FILE_DIR)/$(notdir $(1:.ld.S=.ld)))
endef

##################################
# Processing
##################################

# Create targets for resource files
# $(info Resources: $(ALL_RESOURCES))
$(eval $(if $(ALL_RESOURCES),$(call CREATE_ALL_RESOURCE_TARGETS,$(ALL_RESOURCES))))
LINK_LIBS += $(RESOURCES_LIBRARY)

# $(info Components: $(COMPONENTS))
# Create targets for components
ifeq (app, $(BINS))
$(foreach comp,$(COMPONENTS),$(eval $(if $($(comp)_TYPE), $(if $(filter app app&framework app&kernel share, $($(comp)_TYPE)), $(call BUILD_COMPONENT_RULES,$(comp))), $(call BUILD_COMPONENT_RULES,$(comp)))))
else ifeq (framework, $(BINS))
$(foreach comp,$(COMPONENTS),$(eval $(if $(filter framework app&framework framework&kernel share, $($(comp)_TYPE)), $(call BUILD_COMPONENT_RULES,$(comp)))))
else ifeq (kernel, $(BINS))
$(foreach comp,$(COMPONENTS),$(eval $(if $(filter kernel app&kernel framework&kernel share, $($(comp)_TYPE)), $(call BUILD_COMPONENT_RULES,$(comp)))))
else ifeq (,$(BINS))
$(foreach comp,$(COMPONENTS),$(eval $(call BUILD_COMPONENT_RULES,$(comp))))
endif

# handle lds file, lds -> ld
$(foreach ldsfile,$(AOS_SDK_LDS_FILES),$(eval $(call PROCESS_LDS_FILE,$(ldsfile))))
$(foreach ldsfile,$(AOS_SDK_LDS_INCLUDES),$(eval $(call PROCESS_LDS_FILE,$(ldsfile))))
$(foreach ldsfile,$(AOS_SDK_LDS_FILES),$(eval AOS_SDK_LDFLAGS += -T $(notdir $(ldsfile:.ld.S=.ld))))
$(if $(AOS_SDK_LDS_FILES),$(eval AOS_SDK_LDFLAGS += -L $(LDS_FILE_DIR)))

# Add pre-built libraries
LINK_LIBS += $(AOS_SDK_PREBUILT_LIBRARIES)

##################################
# Build rules
##################################

$(LIBS_DIR):
	$(QUIET)$(call MKDIR, $@)

$(LDS_FILE_DIR):
	$(QUIET)$(call MKDIR, $@)

# Directory dependency - causes mkdir to be called once for each directory.
%/.d:
	$(QUIET)$(call MKDIR, $(dir $@))
	$(QUIET)$(TOUCH) $(@)

$(LINK_OPTS_FILE): $(OUTPUT_DIR)/config.mk $(LDS_FILES)
#$(COMPILER_SPECIFIC_LINK_MAP) $(MAP_OUTPUT_FILE) $(LINK_OPTS_FILE)
	$(QUIET)$(call WRITE_FILE_CREATE, $@ ,$(AOS_SDK_LINK_SCRIPT_CMD) $(call COMPILER_SPECIFIC_LINK_MAP,$(MAP_OUTPUT_FILE))  $(call COMPILER_SPECIFIC_LINK_FILES, $(AOS_SDK_LINK_FILES) $(filter %.a,$^) $(LINK_LIBS)) $(AOS_SDK_LDFLAGS) )

$(LINT_OPTS_FILE): $(LINK_LIBS)
	$(QUIET)$(call WRITE_FILE_CREATE, $@ , )
	$(QUIET)$(foreach opt,$(sort $(subst \",",$(LINT_FLAGS))) $(sort $(LINT_FILES)),$(call WRITE_FILE_APPEND, $@ ,$(opt)))
	
$(LINK_OUTPUT_FILE): $(LINK_LIBS) $(AOS_SDK_LINK_SCRIPT) $(LINK_OPTS_FILE) $(LINT_DEPENDENCY) | $(EXTRA_PRE_LINK_TARGETS)
	$(QUIET)$(ECHO) Making $(notdir $@)
	$(QUIET)$(LINKER) -o  $@ $(OPTIONS_IN_FILE_OPTION)$(LINK_OPTS_FILE) $(COMPILER_SPECIFIC_STDOUT_REDIRECT)
	$(QUIET)$(ECHO_BLANK_LINE)
	$(QUIET)$(call COMPILER_SPECIFIC_MAPFILE_TO_CSV,$(MAP_OUTPUT_FILE),$(MAP_CSV_OUTPUT_FILE))
	
# Stripped elf file target - Strips the full elf file and outputs to a new .stripped.elf file
$(STRIPPED_LINK_OUTPUT_FILE): $(LINK_OUTPUT_FILE)
	$(QUIET)$(STRIP) -o $@ $(STRIPFLAGS) $<
	
# Bin file target - uses objcopy to convert the stripped elf into a binary file
$(BIN_OUTPUT_FILE): $(STRIPPED_LINK_OUTPUT_FILE)
	$(QUIET)$(ECHO) Making $(notdir $@)
	$(QUIET)$(OBJCOPY) -O binary -R .eh_frame -R .init -R .fini -R .comment -R .ARM.attributes $< $@
	
$(HEX_OUTPUT_FILE): $(STRIPPED_LINK_OUTPUT_FILE)
	$(QUIET)$(ECHO) Making $(notdir $@)
	$(QUIET)$(OBJCOPY) -O ihex -R .eh_frame -R .init -R .fini -R .comment -R .ARM.attributes $< $@
# Linker output target - This links all component & resource libraries and objects into an output executable
# CXX is used for compatibility with C++
#$(AOS_SDK_CONVERTER_OUTPUT_FILE): $(LINK_OUTPUT_FILE)
#	$(QUIET)$(ECHO) Making $(notdir $@)
#	$(QUIET)$(CONVERTER) "--ihex" "--verbose" $(LINK_OUTPUT_FILE) $@

#$(AOS_SDK_FINAL_OUTPUT_FILE): $(AOS_SDK_CONVERTER_OUTPUT_FILE)
#	$(QUIET)$(ECHO) Making $(PYTHON_FULL_NAME) $(AOS_SDK_CHIP_SPECIFIC_SCRIPT) -i $(AOS_SDK_CONVERTER_OUTPUT_FILE) -o $(AOS_SDK_FINAL_OUTPUT_FILE)
#	$(QUIET)$(PYTHON_FULL_NAME) $(AOS_SDK_CHIP_SPECIFIC_SCRIPT) -i $(AOS_SDK_CONVERTER_OUTPUT_FILE) -o $(AOS_SDK_FINAL_OUTPUT_FILE)

display_map_summary: $(LINK_OUTPUT_FILE) $(AOS_SDK_CONVERTER_OUTPUT_FILE) $(AOS_SDK_FINAL_OUTPUT_FILE)
	$(QUIET) $(call COMPILER_SPECIFIC_MAPFILE_DISPLAY_SUMMARY,$(MAP_OUTPUT_FILE))

# Main Target - Ensures the required parts get built
# $(info Prebuild targets:$(EXTRA_PRE_BUILD_TARGETS))
# $(info $(BIN_OUTPUT_FILE))
build_done: $(EXTRA_PRE_BUILD_TARGETS) $(BIN_OUTPUT_FILE) $(HEX_OUTPUT_FILE) display_map_summary

$(EXTRA_POST_BUILD_TARGETS): build_done

$(BUILD_STRING): $(if $(EXTRA_POST_BUILD_TARGETS),$(EXTRA_POST_BUILD_TARGETS),build_done)
