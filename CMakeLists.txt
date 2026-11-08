cmake_minimum_required(VERSION 3.20)

project(SoftBodyDriver VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

option(SB_BUILD_TESTS "Build unit tests" ON)
option(SB_BUILD_APPS "Build command line tools (sbsim)" ON)
option(SB_WARNINGS_AS_ERRORS "Treat compiler warnings as errors" OFF)
option(SB_BUILD_GDEXTENSION "Build the Godot 4 GDExtension (downloads godot-cpp)" OFF)

# macOS: build universal binaries (Apple Silicon + Intel) unless overridden.
if(APPLE AND NOT CMAKE_OSX_ARCHITECTURES)
  set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64" CACHE STRING "" FORCE)
endif()

# The GDExtension links godot-cpp, which uses the static MSVC runtime (/MT). Every target that
# ends up in the same DLL (sbcore included) must use the same runtime, so set it before any
# target is created.
if(MSVC AND SB_BUILD_GDEXTENSION)
  set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded" CACHE STRING "MSVC runtime" FORCE)
endif()

add_library(sb_warnings INTERFACE)
if(MSVC)
  target_compile_options(sb_warnings INTERFACE /W4 /permissive- /utf-8)
  if(SB_WARNINGS_AS_ERRORS)
    target_compile_options(sb_warnings INTERFACE /WX)
  endif()
else()
  target_compile_options(sb_warnings INTERFACE -Wall -Wextra -Wpedantic -Wshadow -Wconversion -Wno-sign-conversion)
  if(SB_WARNINGS_AS_ERRORS)
    target_compile_options(sb_warnings INTERFACE -Werror)
  endif()
endif()

add_subdirectory(core)

if(SB_BUILD_GDEXTENSION)
  add_subdirectory(gdextension)
endif()

if(SB_BUILD_APPS)
  add_subdirectory(apps/sbsim)
endif()

if(SB_BUILD_TESTS)
  enable_testing()
  add_subdirectory(core/tests)
endif()
