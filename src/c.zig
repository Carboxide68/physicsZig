
pub usingnamespace @cImport({

    @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "1");
    @cInclude("cimgui.h");
    @cInclude("generator/output/cimgui_impl.h");
    @cUndef("CIMGUI_DEFINE_ENUMS_AND_STRUCTS");

    @cInclude("GL/glew.h");

});
