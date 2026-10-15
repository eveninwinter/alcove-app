require 'xcodeproj'
require 'json'
p = Xcodeproj::Project.open('ios/App/App.xcodeproj')
profiles = JSON.parse(File.read(ENV.fetch('PROFILE_MAP')))
base = 'com.luna.alcove'
registered = base + '.UA72DSC5XZ'
seen = []
p.targets.each do |t|
  t.build_configurations.each do |c|
    old = c.build_settings['PRODUCT_BUNDLE_IDENTIFIER']
    next unless old && (old == base || old.start_with?(base + '.'))
    id = registered + old.delete_prefix(base)
    profile = profiles.fetch(id)
    seen << id
    c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = id
    c.build_settings['DEVELOPMENT_TEAM'] = 'UA72DSC5XZ'
    c.build_settings['CODE_SIGN_STYLE'] = 'Manual'
    c.build_settings['CODE_SIGN_IDENTITY'] = 'Apple Distribution'
    c.build_settings['PROVISIONING_PROFILE_SPECIFIER'] = profile.fetch('uuid')
    c.build_settings['CODE_SIGN_ENTITLEMENTS'] = profile.fetch('entitlements')
    c.build_settings['CURRENT_PROJECT_VERSION'] = ENV.fetch('BUILD_NUMBER')
  end
end
raise 'Expected all three targets' unless seen.uniq.sort == profiles.keys.sort
p.save
