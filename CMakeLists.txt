cmake_minimum_required(VERSION 3.20)
project(WaterSurfaceWallpaper LANGUAGES NONE)

# ---------------------------------------------------------------------------
# Locate qsb — the Qt shader compiler that turns .vert/.frag (Vulkan GLSL)
# into the .qsb binary packages consumed by Qt Quick's ShaderEffect at runtime.
# On most Linux distributions it is NOT on $PATH, so we hint at the Qt6 libexec
# and bin directories.
# ---------------------------------------------------------------------------
find_program(QSB_TOOL qsb
    HINTS
        "/usr/lib64/qt6/bin"
        "/usr/lib/qt6/bin"
        "/usr/lib/x86_64-linux-gnu/qt6/bin"
        "${Qt6_DIR}/../../../bin"
        "${Qt6_DIR}/../../../libexec"
    REQUIRED
)

message(STATUS "qsb found: ${QSB_TOOL}")

# ---------------------------------------------------------------------------
# Shader sources — every .frag and .vert gets compiled to a companion .qsb.
# The .qsb files are written alongside the source files so they are part of
# the package tree and require no separate install step.
# ---------------------------------------------------------------------------
set(SHADER_DIR "${CMAKE_CURRENT_SOURCE_DIR}/water-surface/shaders")

set(SHADER_SOURCES
    "${SHADER_DIR}/water_physics.vert"
    "${SHADER_DIR}/water_physics.frag"
    "${SHADER_DIR}/water_render.vert"
    "${SHADER_DIR}/water_render.frag"
    "${SHADER_DIR}/water_transition.vert"
    "${SHADER_DIR}/water_transition.frag"
)

set(SHADER_QSB_OUTPUTS "")

foreach(SHADER_SRC ${SHADER_SOURCES})
    set(QSB_OUT "${SHADER_SRC}.qsb")
    list(APPEND SHADER_QSB_OUTPUTS "${QSB_OUT}")

    add_custom_command(
        OUTPUT  "${QSB_OUT}"
        COMMAND "${QSB_TOOL}"
                # Target these GLSL versions so Qt RHI can pick the best one
                # for the active backend (Vulkan, OpenGL 3.x, OpenGL ES 3.x).
                --glsl "100 es,120,150"
                --hlsl 50
                --msl 12
                -o "${QSB_OUT}"
                "${SHADER_SRC}"
        DEPENDS "${SHADER_SRC}"
        COMMENT "Compiling shader: ${SHADER_SRC}"
        VERBATIM
    )
endforeach()

# The 'shaders' target drives all shader compilations when you run:
#   cmake --build build
add_custom_target(shaders ALL DEPENDS ${SHADER_QSB_OUTPUTS})
