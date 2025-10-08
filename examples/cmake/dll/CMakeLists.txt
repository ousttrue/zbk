# project
cmake_minimum_required(VERSION 3.20.0)
project(hello VERSION 0.1.0)

# target
set(TARGET_NAME ${PROJECT_NAME})
add_library(${TARGET_NAME} SHARED hello.c)
set_target_properties(${TARGET_NAME} PROPERTIES PUBLIC_HEADER "hello.h")
install(TARGETS ${TARGET_NAME})
