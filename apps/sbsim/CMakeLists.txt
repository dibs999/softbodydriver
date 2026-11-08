add_executable(sbsim main.cpp)
target_link_libraries(sbsim PRIVATE sb::core sb_warnings)
