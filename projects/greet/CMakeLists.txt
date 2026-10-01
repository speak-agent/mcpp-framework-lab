# A small CMake subproject that stands in for a vendored library: one shared
# library, installed with the layout `install()` gives it. Every case builds it
# through the plugins' deps-cmake member, so the cmake that runs is the one
# whose source the case states.
cmake_minimum_required(VERSION 3.16)
project(greet LANGUAGES C)

add_library(greet SHARED greet.c)
target_include_directories(greet PUBLIC $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>)
set_target_properties(greet PROPERTIES WINDOWS_EXPORT_ALL_SYMBOLS ON)

install(TARGETS greet RUNTIME DESTINATION bin LIBRARY DESTINATION lib ARCHIVE DESTINATION lib)
install(FILES include/greet.h DESTINATION include)
