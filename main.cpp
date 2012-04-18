#if defined(WIN32) || defined(__WIN32__)
#include <windows.h>
#endif //WIN32

#include <deque>
#include <cstdio>
#include <cstdlib>
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
bool              LUA_QUIT = false;
int               CH = 0;

enum NetState{
    N_DEFAULT,
    N_CONNECTED_SERV,
    N_MATCHED,
    N_CONNECTED_DEV
};
enum GameState{
    G_DEFAULT,
    G_MATCHED
};
NetState  N_STATE = N_DEFAULT;
GameState G_STATE = G_DEFAULT;

void start_lua(char ch)
{
    L = luaL_newstate();
    luaL_openlibs(L);
    Lua::run_script(L, "eventloop.lua");

    if( ch == 's' ){
        Lua::call(L, "init", 1); //client
        Lua::call(L, "run"); //server
    }else if(ch=='c'){
        Lua::call(L, "init", 2); //client
        Lua::call(L, "run"); //server
    }

    printf("C: Returned back to C.\n");
    {
        boost::mutex::scoped_lock l(MQ_MUTEX);
        MQ.clear();
    }
    N_STATE = N_DEFAULT;
    LUA_QUIT =  false;
    lua_close(L);
    L = 0;
    printf("C: Lua State really closed.\n");
}

extern "C" {
    APIEXPORT void on_connected() {
        printf("Lua->C: farside connected.\n");
        N_STATE = N_CONNECTED_SERV;
    }

    APIEXPORT void on_matched() {
        printf("Lua->C: farside matched.\n");
        N_STATE = N_MATCHED;
    }

    APIEXPORT void on_disconnected() {
        printf("Lua->C: farside disconnected.\n");
        N_STATE = N_DEFAULT;
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
#if defined(WIN32) || defined(__WIN32__)
        Sleep(1);
#else   //NOT WIN32
        usleep(1000);
#endif  //WIN32
        CH = getc(stdin);
        getc(stdin); //eat Return
        printf("%c", CH);
    }
}

int main()
{
    using std::tr1::bind;
    boost::thread* thLua  = 0;
    boost::thread  thInput( input_loop );

    while ( CH != 3 ) { //ctrl-c
#if defined(WIN32) || defined(__WIN32__)
        Sleep(250);
#else   //NOT WIN32
        usleep(250000);
#endif  //WIN32
        if( CH == 's' || CH == 'c' ) {
            if( !L ) {
                if( thLua ) {
                    delete thLua;
                    thLua = 0;
                }
                thLua = new boost::thread( bind(start_lua, CH) );
            }
        }
        else if( CH == 'p' ) {
            if( L ) {
                LUA_QUIT = true;
            }
        }
        else if( CH >= '1' && CH <= '4' ) {
            if( L && thLua && N_STATE == N_MATCHED ) {
                boost::mutex::scoped_lock l(MQ_MUTEX);
                MQ.push_back(CH);
            }
        }
        CH = 0; //reset CH here
    }
    return 0;
}
