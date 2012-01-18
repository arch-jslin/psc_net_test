#include <windows.h>
#include <deque>
#include <cstdio>
#include <boost/thread/thread.hpp>
#include <boost/thread/mutex.hpp>
#include <boost/tr1/functional.hpp>
#include "lua_utils.hpp"

#ifdef WIN32
#define APIEXPORT __declspec(dllexport)
#else
#define APIEXPORT
#endif

boost::mutex      MQ_MUTEX;

std::deque<int>   MQ;
lua_State*        L = 0;
bool              CONNECTED = false;
bool              LUA_QUIT = false;
int               CH = 0;

void start_lua(char ch)
{
    L = luaL_newstate();
    luaL_openlibs(L);
    Lua::run_script(L, "eventloop.lua");

    if( ch == 's' )
        Lua::call(L, "run", 1); //server
    else
        Lua::call(L, "run", 2); //client

    printf("C: Returned back to C.\n");
    {
        boost::mutex::scoped_lock l(MQ_MUTEX);
        MQ.clear();
    }
    CONNECTED = false;
    LUA_QUIT =  false;
    lua_close(L);
    L = 0;
    printf("C: Lua State really closed.\n");
}

extern "C" {
    APIEXPORT void signify_connected() {
        printf("Lua->C: farside connected.\n");
        CONNECTED = true;
    }

    APIEXPORT int poll_from_C() {
        boost::mutex::scoped_lock l(MQ_MUTEX);
        if( !MQ.empty() ) {
            int front = MQ.front();
            MQ.pop_front();
            return front;
        }
        return 0;
    }

    APIEXPORT bool check_quit() {
        return LUA_QUIT;
    }
}

void input_loop()
{
    while( 1 ) {
        Sleep(1);
        CH = getc(stdin);
        getc(stdin); //eat Return
    }
}

int main()
{
    using std::tr1::bind;
    boost::thread* t  = 0;
    boost::thread  t2( input_loop );

    while ( CH != 3 ) { //ctrl-c
        Sleep(250);

        if( CH == 's' || CH == 'c' ) {
            if( !L ) {
                if( t ) {
                    delete t;
                    t = 0;
                }
                t = new boost::thread( bind(start_lua, CH) );
            }
            CH = 0;
        }
        else if( CH == 'p' ) {
            if( L ) {
                LUA_QUIT = true;
            }
            CH = 0;
        }

        if( CONNECTED ) {
            boost::mutex::scoped_lock l(MQ_MUTEX);
            MQ.push_back(65);
        }
    }
    return 0;
}
