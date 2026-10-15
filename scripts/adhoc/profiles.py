import os, pathlib, plistlib, subprocess, json
root=pathlib.Path(os.environ['SIGN_DIR'])
dest=pathlib.Path.home()/'Library/MobileDevice/Provisioning Profiles';dest.mkdir(parents=True,exist_ok=True)
profiles={}
for f in root.glob('*.mobileprovision'):
 p=plistlib.loads(subprocess.check_output(['security','cms','-D','-i',str(f)]))
 ent=p['Entitlements']; app=ent['application-identifier'].removeprefix('UA72DSC5XZ.')
 assert p['TeamIdentifier']==['UA72DSC5XZ'] and not ent.get('get-task-allow')
 assert '00008140-0006455E00A2201C' in p['ProvisionedDevices']
 (dest/(p['UUID']+'.mobileprovision')).write_bytes(f.read_bytes())
 # Fully specified signing entitlements from this app's own profile, not a wildcard keychain group.
 ent=dict(ent);ent['keychain-access-groups']=['UA72DSC5XZ.'+app]
 e=root/(f.stem+'.entitlements');e.write_bytes(plistlib.dumps(ent))
 profiles[app]={'uuid':p['UUID'],'entitlements':str(e)}
pathlib.Path(os.environ['PROFILE_MAP']).write_text(json.dumps(profiles))
options={'method':'release-testing','signingStyle':'manual','teamID':'UA72DSC5XZ','signingCertificate':'Apple Distribution','manageAppVersionAndBuildNumber':False,'provisioningProfiles':{k:v['uuid'] for k,v in profiles.items()}}
(root/'ExportOptions.plist').write_bytes(plistlib.dumps(options))
print('Validated and installed three Ad Hoc profiles' if len(profiles)==3 else 'Unexpected profile count')
assert len(profiles)==3
