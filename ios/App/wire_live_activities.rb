#!/usr/bin/env ruby
# Wires the RugbyLiveActivities plugin + Widget Extension into App.xcodeproj.
# Idempotent: re-running won't duplicate targets/files.
require "xcodeproj"

PROJECT   = "App.xcodeproj"
WIDGET    = "RugbyLiveActivityWidget"
APP_ID    = "ai.rugbycoach.app"
WIDGET_ID = "#{APP_ID}.#{WIDGET}"

proj = Xcodeproj::Project.open(PROJECT)
app  = proj.targets.find { |t| t.name == "App" }
raise "App target not found" unless app

app_group = proj.main_group.children.find { |c| c.display_name == "App" }

# ---------------------------------------------------------------------------
# Helper: find or create a nested group by path under a parent group.
# ---------------------------------------------------------------------------
def find_or_create_group(parent, name, path)
  existing = parent.children.find { |c| c.display_name == name && c.is_a?(Xcodeproj::Project::Object::PBXGroup) }
  return existing if existing
  parent.new_group(name, path)
end

def find_file_ref(group, basename)
  group.files.find { |f| f.display_name == basename }
end

# ---------------------------------------------------------------------------
# 1. Plugin files -> App target
#    App/Plugins/RugbyLiveActivities/{Plugin, Attributes}.swift
# ---------------------------------------------------------------------------
plugins_group = find_or_create_group(app_group, "Plugins", "Plugins")
rla_group     = find_or_create_group(plugins_group, "RugbyLiveActivities", "RugbyLiveActivities")

plugin_ref = find_file_ref(rla_group, "RugbyLiveActivitiesPlugin.swift") ||
             rla_group.new_reference("RugbyLiveActivitiesPlugin.swift")
attrs_ref  = find_file_ref(rla_group, "RugbyMatchAttributes.swift") ||
             rla_group.new_reference("RugbyMatchAttributes.swift")

# Add to App compile sources if not already present.
app_source_files = app.source_build_phase.files_references
app.add_file_references([plugin_ref]) unless app_source_files.include?(plugin_ref)
app.add_file_references([attrs_ref])  unless app.source_build_phase.files_references.include?(attrs_ref)

# ---------------------------------------------------------------------------
# 2. Create the Widget Extension target (if absent)
# ---------------------------------------------------------------------------
widget = proj.targets.find { |t| t.name == WIDGET }
unless widget
  widget = proj.new_target(:app_extension, WIDGET, :ios, "16.1")
end

# Widget source group + files
widget_group = proj.main_group.children.find { |c| c.display_name == WIDGET && c.is_a?(Xcodeproj::Project::Object::PBXGroup) }
widget_group ||= proj.main_group.new_group(WIDGET, WIDGET)

w_widget_ref = find_file_ref(widget_group, "RugbyLiveActivitiesWidget.swift") ||
               widget_group.new_reference("RugbyLiveActivitiesWidget.swift")
w_bundle_ref = find_file_ref(widget_group, "RugbyLiveActivityWidgetBundle.swift") ||
               widget_group.new_reference("RugbyLiveActivityWidgetBundle.swift")
w_plist_ref  = find_file_ref(widget_group, "Info.plist") ||
               widget_group.new_reference("Info.plist")

w_sources = widget.source_build_phase.files_references
widget.add_file_references([w_widget_ref]) unless w_sources.include?(w_widget_ref)
widget.add_file_references([w_bundle_ref]) unless widget.source_build_phase.files_references.include?(w_bundle_ref)
# Shared attributes file: compiled into BOTH targets.
widget.add_file_references([attrs_ref])    unless widget.source_build_phase.files_references.include?(attrs_ref)

# ---------------------------------------------------------------------------
# 3. Widget build settings
# ---------------------------------------------------------------------------
widget.build_configurations.each do |cfg|
  bs = cfg.build_settings
  bs["PRODUCT_BUNDLE_IDENTIFIER"]      = WIDGET_ID
  bs["PRODUCT_NAME"]                   = "$(TARGET_NAME)"
  bs["INFOPLIST_FILE"]                 = "#{WIDGET}/Info.plist"
  bs["GENERATE_INFOPLIST_FILE"]        = "NO"
  bs["IPHONEOS_DEPLOYMENT_TARGET"]     = "16.1"
  bs["SWIFT_VERSION"]                  = "5.0"
  bs["TARGETED_DEVICE_FAMILY"]         = "1,2"
  bs["SKIP_INSTALL"]                   = "YES"
  bs["CODE_SIGN_STYLE"]                = "Automatic"
  bs["CURRENT_PROJECT_VERSION"]        = "1"
  bs["MARKETING_VERSION"]              = "1.0"
  bs["PRODUCT_BUNDLE_PACKAGE_TYPE"]    = "XPC!"
  bs["LD_RUNPATH_SEARCH_PATHS"]        = ["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"]
  bs["SWIFT_EMIT_LOC_STRINGS"]         = "YES"
  bs["ASSETCATALOG_COMPILER_GENERATE_ASSET_SYMBOLS"] = "NO"
  # Mirror codesign-related defaults from the app where helpful.
  bs["ENABLE_USER_SCRIPT_SANDBOXING"]  = "NO"
end

# ---------------------------------------------------------------------------
# 4. App depends on widget + embeds it (Embed App Extensions copy phase)
# ---------------------------------------------------------------------------
# Target dependency
unless app.dependencies.any? { |d| d.target == widget }
  app.add_dependency(widget)
end

# Embed App Extensions copy-files phase (dstSubfolderSpec 13 = PlugIns)
embed_phase = app.copy_files_build_phases.find { |ph| ph.symbol_dst_subfolder_spec == :plug_ins }
unless embed_phase
  embed_phase = app.new_copy_files_build_phase("Embed App Extensions")
  embed_phase.symbol_dst_subfolder_spec = :plug_ins
  embed_phase.dst_path = ""
end

product_ref = widget.product_reference
unless embed_phase.files_references.include?(product_ref)
  bf = embed_phase.add_file_reference(product_ref)
  bf.settings = { "ATTRIBUTES" => ["RemoveHeadersOnCopy"] }
end

# ---------------------------------------------------------------------------
# 5. Ensure the App target's deployment target supports the plugin (15.0 is fine
#    because of @available guards) — leave as-is. Just save.
# ---------------------------------------------------------------------------
proj.save
puts "OK: wired plugin + #{WIDGET} extension."
puts "Targets now: #{proj.targets.map(&:name).join(', ')}"
