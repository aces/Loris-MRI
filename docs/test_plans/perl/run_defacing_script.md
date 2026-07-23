### Test plan

- [ ] Make sure that the command `which pipeline_qc_face.pl` points to the file in `uploadNeuroDB/bin` and not the one in the MINC tools

- [ ] Set up the following settings in the Config module under the “Imaging Pipeline” section:
- “Scan type to use as a reference for defacing...”: select the T1W scan type (t1 in raisinbread)
- “Modalities on which to run the defacing pipeline”: select the modalities to deface (flair, t1, t2, pd in raisinbread)

- [ ] Run defacing pipeline on SessionID 2145 (DCC292_676061_V1):
```
run_defacing_script.pl -profile $profile -sessionIDs $session_id
```

- [ ] Check sessionID was defaced:
```
SELECT COUNT(*) FROM files f JOIN mri_scan_type USING (MriScanTypeID) WHERE MriScanTypeName='t1' AND SessionID=2145;
SELECT COUNT(*) FROM files f JOIN mri_scan_type USING (MriScanTypeID) WHERE MriScanTypeName='t1-defaced' AND SessionID=2145;
```

