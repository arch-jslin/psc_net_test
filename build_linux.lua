os.execute [[gcc -I/usr/local/include/luajit-2.0 -L/usr/local/lib -lluajit-5.1 -lboost_thread-mt -O1 -Os -Wl,-E -o psc_net_test lua_utils.cpp main.cpp]]

os.execute [[mv psc_net_test bin/Release]]

os.execute [[export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH]]
