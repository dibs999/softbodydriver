#include "register_types.h"

#include <gdextension_interface.h>

#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "sb_vehicle.h"
#include "sb_world.h"

using namespace godot;

void initialize_softbodydriver(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) return;
    GDREGISTER_CLASS(SBVehicle);
    GDREGISTER_CLASS(SBWorld);
}

void uninitialize_softbodydriver(ModuleInitializationLevel p_level) {
    (void)p_level;
}

extern "C" {
GDExtensionBool GDE_EXPORT softbodydriver_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address,
                                                      const GDExtensionClassLibraryPtr p_library,
                                                      GDExtensionInitialization* r_initialization) {
    godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
    init_obj.register_initializer(initialize_softbodydriver);
    init_obj.register_terminator(uninitialize_softbodydriver);
    init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init_obj.init();
}
}
