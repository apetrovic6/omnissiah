{config, ...}:
{

  imports = [../../../stylix/colors.nix];

programs.walker.themes.ugala =  with config.hyperium.palette; {
    # Check out the default css theme as an example https://github.com/abenz1267/walker/blob/master/resources/themes/default/style.css
    style =  /* css */ ''
     * {
  all: unset;
}

.normal-icons {
  -gtk-icon-size: 16px;
}

.large-icons {
  -gtk-icon-size: 32px;
}

scrollbar {
  opacity: 0;
}

.box-wrapper {
  box-shadow:
    0 19px 38px rgba(0, 0, 0, 0.3),
    0 15px 12px rgba(0, 0, 0, 0.22);
  background: alpha(${backgroundDefault}, 0.8);
  padding: 20px;
  border-radius: 20px;
  border: 1px solid alpha(${border}, 0.75);
}

.preview-box,
.elephant-hint,
.placeholder {
  color: ${textDefault};
}

.box {
}

.search-container {
  border-radius: 10px;
}

.input placeholder {
  opacity: 0.5;
}

.input {
  caret-color: @selected-text;
  background: darker(${backgroundAlpha50});
  padding: 10px;
}

.input:focus,
.input:active {
}

.content-container {
}

.placeholder {
}

.scroll {
}

.list {
  color: ${textDefault};
}

child {
}

.item-box {
  border-radius: 10px;
  padding: 10px;
}

.item-quick-activation {
  margin-left: 10px;
  background: alpha(${background}, 0.25);
  border-radius: 5px;
  padding: 10px;
}

child:hover .item-box,
child:selected .item-box {
  background: darker(alpha(${backgroundDefault}, 0.5));
}

.item-text-box {
}

.item-text {
}

.item-subtext {
  font-size: 12px;
  opacity: 0.5;
}

.item-image,
.item-image-text {
  margin-right: 10px;
}

.item-image-text {
  font-size: 28px;
}

.preview {
  border: 1px solid alpha(${border}, 0.25);
  padding: 10px;
  border-radius: 10px;
  color: ${foreground};
}

.calc .item-text {
  font-size: 24px;
}

.calc .item-subtext {
}

.symbols .item-image {
  font-size: 24px;
}

.todo.done .item-text-box {
  opacity: 0.25;
}

.todo.urgent {
  font-size: 24px;
}

.todo.active {
  font-weight: bold;
}

.bluetooth.disconnected {
  opacity: 0.5;
}

.preview .large-icons {
  -gtk-icon-size: 64px;
}

.keybinds-wrapper {
  border-top: 1px solid darker(${border});
  font-size: 12px;
  opacity: 0.5;
  color: #${backgroundDefault};
}

.keybinds {
}

.keybind {
}

.keybind-bind {
  color: lighter(${textAlternate});
  font-weight: bold;
}

.keybind-label {
}      '';

    # Check out the default layouts for examples https://github.com/abenz1267/walker/tree/master/resources/themes/default
    layouts = {
      "layout" = 
        ''
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
        <property name="width-request">644</property>
        <property name="overflow">hidden</property>
        <property name="orientation">horizontal</property>
        <property name="valign">center</property>
        <property name="halign">center</property>
        <child>
          <object class="GtkBox" id="Box">
            <style>
              <class name="box"></class>
            </style>
            <property name="orientation">vertical</property>
            <property name="hexpand-set">true</property>
            <property name="hexpand">true</property>
            <property name="spacing">10</property>
            <child>
              <object class="GtkBox" id="SearchContainer">
                <style>
                  <class name="search-container"></class>
                </style>
                <property name="overflow">hidden</property>
                <property name="orientation">horizontal</property>
                <property name="halign">fill</property>
                <property name="hexpand-set">true</property>
                <property name="hexpand">true</property>
                <child>
                  <object class="GtkEntry" id="Input">
                    <style>
                      <class name="input"></class>
                    </style>
                    <property name="halign">fill</property>
                    <property name="hexpand-set">true</property>
                    <property name="hexpand">true</property>
                  </object>
                </child>
              </object>
            </child>
            <child>
              <object class="GtkBox" id="ContentContainer">
                <style>
                  <class name="content-container"></class>
                </style>
                <property name="orientation">horizontal</property>
                <property name="spacing">10</property>
                <property name="vexpand">true</property>
                <property name="vexpand-set">true</property>
                <child>
                  <object class="GtkLabel" id="ElephantHint">
                    <style>
                      <class name="elephant-hint"></class>
                    </style>
                    <property name="hexpand">true</property>
                    <property name="height-request">100</property>
                    <property name="label">Waiting for elephant...</property>
                  </object>
                </child>
                <child>
                  <object class="GtkLabel" id="Placeholder">
                    <style>
                      <class name="placeholder"></class>
                    </style>
                    <property name="label">No Results</property>
                    <property name="yalign">0.0</property>
                    <property name="hexpand">true</property>
                  </object>
                </child>
                <child>
                  <object class="GtkScrolledWindow" id="Scroll">
                    <style>
                      <class name="scroll"></class>
                    </style>
                    <property name="hexpand">true</property>
                    <property name="can_focus">false</property>
                    <property name="overlay-scrolling">true</property>
                    <property name="max-content-width">600</property>
                    <property name="max-content-height">300</property>
                    <property name="min-content-height">0</property>
                    <property name="propagate-natural-height">true</property>
                    <property name="propagate-natural-width">true</property>
                    <property name="hscrollbar-policy">automatic</property>
                    <property name="vscrollbar-policy">automatic</property>
                    <child>
                      <object class="GtkGridView" id="List">
                        <style>
                          <class name="list"></class>
                        </style>
                        <property name="max_columns">1</property>
                        <property name="can_focus">false</property>
                      </object>
                    </child>
                  </object>
                </child>
                <child>
                  <object class="GtkBox" id="Preview">
                    <style>
                      <class name="preview"></class>
                    </style>
                  </object>
                </child>
              </object>
            </child>
            <child>
              <object class="GtkLabel" id="Error">
                <style>
                  <class name="error"></class>
                </style>
                <property name="xalign">0</property>
               <property name="visible">false</property>
              </object>
            </child>
          </object>
        </child>
      </object>
    </child>
  </object>
</interface>
        '';
    "item_calc" = " <!-- xml --> ";
    #   # other provider layouts
     };
  };
}
