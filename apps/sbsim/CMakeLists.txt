add_executable(sbsim main.cpp)
target_link_libraries(sbsim PRIVATE sb::core sb_warnings)

add_executable(cartest cartest.cpp)
target_link_libraries(cartest PRIVATE sbcore sb_warnings)

add_executable(stabilitybench stabilitybench.cpp)
target_link_libraries(stabilitybench PRIVATE sb::core sb_warnings)
target_include_directories(stabilitybench SYSTEM PRIVATE ${PROJECT_SOURCE_DIR}/third_party)
if(SB_BUILD_TESTS)
  # Apps are configured before the root testing block. Enable this directory
  # explicitly so its calibration test is emitted into CTestTestfile.cmake.
  enable_testing()
  add_test(NAME stability_spectral_calibration COMMAND stabilitybench --self-test)
endif()
