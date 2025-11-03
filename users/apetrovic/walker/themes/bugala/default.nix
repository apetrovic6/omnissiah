{config,...}:
{
imports = [
    ../../../stylix/colors.nix
  ];

programs.walker.themes.bugala = {
      style = /*css*/ ''
@define-color window_bg_color rgba(0, 0, 0, 0.8);;
@define-color accent_bg_color rgba(255, 255, 255, 0.1);
@define-color theme_fg_color #ffffff;

* {
  all: unset;
}

.box-wrapper {
  background: @window_bg_color;
  padding: 15px;
  border-radius: 12px;
  border: 1px solid rgba(255, 255, 255, 0.1);
}

.input {
  background: @accent_bg_color;
  color: @theme_fg_color;
  padding: 10px;
  border-radius: 8px;
}

.item-box {
  padding: 10px;
  border-radius: 8px;
}

child:selected .item-box {
  background: rgba(255, 255, 255, 0.2);
}
  '';

   layouts = {
"layout" = ''

<?xml version="1.0" encoding="UTF-8"?>
<interface>
  <requires lib="gtk" version="4.0"></requires>
  <object class="GtkWindow" id="Window">
    <style>
      <class name="window"></class>
    </style>
    <property name="resizable">true</property>
    <property name="title">Walker</property>
    <child>
      <object class="GtkBox" id="BoxWrapper">
        <style>
          <class name="box-wrapper"></class>
        </style>
        <property name="orientation">horizontal</property>
        <property name="valign">center</property>
        <property name="halign">center</property>
        <property name="width-request">600</property>
        <property name="height-request">550</property>
        <!-- Content here -->
      </object>
    </child>
  </object>
</interface>
        '';
    } ;
  };
}
