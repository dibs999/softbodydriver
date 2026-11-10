# GDExtension that exposes the soft-body physics core to Godot 4.5+.
#
# Built from the repository root with:
#   cmake -S . -B build-gd -DSB_BUILD_GDEXTENSION=ON -DSB_BUILD_TESTS=OFF -DSB_BUILD_APPS=OFF
#   cmake --build build-gd --config Release
# The library is written to game/bin/ where game/softbodydriver.gdextension finds it.
include(FetchContent)

set(SB_GODOTCPP_DIR "" CACHE PATH "Use an existing godot-cpp checkout instead of downloading it")
set(GODOTCPP_DISABLE_EXCEPTIONS OFF CACHE BOOL "" FORCE)
if(NOT GODOTCPP_TARGET)
  set(GODOTCPP_TARGET "template_debug" CACHE STRING "template_debug | template_release | editor")
endif()

if(SB_GODOTCPP_DIR)
  add_subdirectory(${SB_GODOTCPP_DIR} ${CMAKE_BINARY_DIR}/godot-cpp)
else()
  FetchContent_Declare(
    godotcpp
    GIT_REPOSITORY https://github.com/godotengine/godot-cpp.git
    GIT_TAG godot-4.5-stable
    GIT_SHALLOW TRUE)
  FetchContent_MakeAvailable(godotcpp)
endif()

add_library(softbodydriver_gd SHARED
  src/register_types.cpp
  src/sb_world.cpp
  src/sb_vehicle.cpp
  src/sb_prop.cpp
)
target_link_libraries(softbodydriver_gd PRIVATE godot-cpp sbcore)
get_target_property(GODOTCPP_SUFFIX godot-cpp GODOTCPP_SUFFIX)

set(SB_GD_OUTPUT_DIR "${PROJECT_SOURCE_DIR}/game/bin/")
set_target_properties(softbodydriver_gd PROPERTIES
  CXX_STANDARD 20
  CXX_EXTENSIONS OFF
  CXX_VISIBILITY_PRESET hidden
  POSITION_INDEPENDENT_CODE ON
  BUILD_RPATH_USE_ORIGIN ON
  LIBRARY_OUTPUT_DIRECTORY "$<1:${SB_GD_OUTPUT_DIR}>"
  RUNTIME_OUTPUT_DIRECTORY "$<1:${SB_GD_OUTPUT_DIR}>"
  PDB_OUTPUT_DIRECTORY "$<1:${SB_GD_OUTPUT_DIR}>"
  PREFIX "lib"
  OUTPUT_NAME "softbodydriver${GODOTCPP_SUFFIX}"
)
if(MSVC)
  target_compile_options(softbodydriver_gd PRIVATE /utf-8 /EHsc)
endif()
