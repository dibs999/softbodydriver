add_executable(sbsim main.cpp)
target_link_libraries(sbsim PRIVATE sb::core sb_warnings)

add_executable(cartest cartest.cpp)
target_link_libraries(cartest PRIVATE sbcore sb_warnings)
