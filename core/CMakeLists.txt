add_library(sbcore STATIC
  src/builders.cpp
  src/colliders.cpp
  src/recorder.cpp
  src/sbeam_io.cpp
  src/scenes.cpp
  src/softbody.cpp
  src/world.cpp
)
add_library(sb::core ALIAS sbcore)

target_include_directories(sbcore
  PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include
)
# nlohmann/json is an implementation detail (not exposed in public headers).
target_include_directories(sbcore SYSTEM PRIVATE ${PROJECT_SOURCE_DIR}/third_party)
target_link_libraries(sbcore PRIVATE sb_warnings)
set_target_properties(sbcore PROPERTIES POSITION_INDEPENDENT_CODE ON)  # needed for the Godot GDExtension later
