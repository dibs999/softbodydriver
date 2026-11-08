set(SBCORE_SOURCES
  src/builders.cpp
  src/c_api.cpp
  src/colliders.cpp
  src/powertrain.cpp
  src/recorder.cpp
  src/sbeam_io.cpp
  src/scenes.cpp
  src/softbody.cpp
  src/vehicle.cpp
  src/wheel.cpp
  src/world.cpp
)

add_library(sbcore STATIC ${SBCORE_SOURCES})
add_library(sb::core ALIAS sbcore)

target_include_directories(sbcore
  PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include
)
# nlohmann/json is an implementation detail (not exposed in public headers).
target_include_directories(sbcore SYSTEM PRIVATE ${PROJECT_SOURCE_DIR}/third_party)
target_link_libraries(sbcore PRIVATE sb_warnings)
set_target_properties(sbcore PROPERTIES POSITION_INDEPENDENT_CODE ON)

# Shared library for Godot 4 (GDExtension / FFI) and Python ctypes on Win/Mac/Linux.
add_library(sbcore_shared SHARED ${SBCORE_SOURCES})
target_include_directories(sbcore_shared PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_include_directories(sbcore_shared SYSTEM PRIVATE ${PROJECT_SOURCE_DIR}/third_party)
target_link_libraries(sbcore_shared PRIVATE sb_warnings)
set_target_properties(sbcore_shared PROPERTIES OUTPUT_NAME "sbcore")
