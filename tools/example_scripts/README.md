### Example scripts

 - **deletemincsqlwrapper.pl**
   - An example script to delete multiple minc files fitting a common criterion from the database. 
   - The script also provides the option to re-insert deleted scans with their seriesUID when using the `-insertminc` flag.
   - **Projects should modify the query as needed to suit their needs**. 
   - For the example query provided (in `$queryF`), all inserted scans with types like `t1` or `t2`, having a `slice thickness` in the range of `4 mm` will be deleted.
      - A use case of this deletion query might be that initially the project did not exclude `t1` or `t2` modalities having 4 mm slice thickness, and subsequently, the
        study `mri_protocol` has been changed to add tighter checks on slice thickness.  


