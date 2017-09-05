### Example scripts

 - **deletemincsqlwrapper.pl**
   - An example script to delete multiple minc files fitting a common criterion from the database. **Projects should modify as needed to suit their needs**. 
    More specifically, the provided query (in `$queryF`) deletes all inserted scans with types like `t1` or `t2`, having a `slice thickness` in the range of `4 mm`. 
    The script also provides the option to re-insert deleted scans with their seriesUID when using the `-insertminc` flag.


