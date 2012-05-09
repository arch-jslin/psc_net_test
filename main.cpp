#if defined(WIN32) || defined(__WIN32__)
#include <windows.h>
#endif //WIN32

#include <deque>
#include <cstdio>
#include <cstdlib>
#include <boost/thread/thread.hpp>
#include <boost/tr1/functional.hpp>
#include "lua_utils.hpp"

#ifdef WIN32
#define APIEXPORT __declspec(dllexport)
#else
#define APIEXPORT
#endif

std::deque<std::string> MQ;
lua_State*              L = 0;
bool                    LUA_QUIT = false;
int                     CH = 0;

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

void end_lua();
void start_lua(char ch)
{
    L = luaL_newstate();
    luaL_openlibs(L);
    Lua::run_script(L, "eventloop.lua");

    bool get_lobby = false;
    if( ch == 's' ) {
        get_lobby = Lua::call_R<bool>(L, "init", 1); //server
    }
    else {
        get_lobby = Lua::call_R<bool>(L, "init", 2); //client
    }
    if ( !get_lobby ) {
        printf("C: notified by lua that connecting to lobby server failed.\n");
        end_lua();
    }
}

void process_lua()
{
    Lua::call(L, "run");
}

void end_lua()
{
    Lua::call(L, "dtor");
    printf("C: Lua cleaned up.\n");

    MQ.clear();

    N_STATE = N_DEFAULT;
    LUA_QUIT =  false;
    lua_close(L);
    L = 0;
    printf("C: Lua State really closed.\n");
}

extern "C" {
    APIEXPORT void on_connected(char const*) {
        printf("Lua->C: server connected.\n");
        N_STATE = N_CONNECTED_SERV;
    }

    APIEXPORT void on_matched(char const*) {
        printf("Lua->C: farside matched.\n");
        N_STATE = N_MATCHED;
    }

    APIEXPORT void on_disconnected(char const*) {
        printf("Lua->C: disconnected.\n");
        N_STATE = N_DEFAULT;
    }

    APIEXPORT void on_received(char const* str) {
        printf("Lua->C: received: %s\n", str);
    }

    APIEXPORT char const* poll_from_C() {
        if( !MQ.empty() ) {
            std::string const& front = MQ.front();
            MQ.pop_front();
            return front.c_str();
        }
        return "";
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
    boost::thread  thInput( input_loop );

    while ( CH != 3 ) { //ctrl-c
        if( !L ) {
            if( CH == 's' || CH == 'c' ) {
                start_lua(CH);
            }
        }
        else {
            if( CH == 'p' ) {
                LUA_QUIT = true;
                end_lua();
                continue;
            }
            else if( CH == '1' ) {
                if( N_STATE >= N_CONNECTED_SERV ) {
                    MQ.push_back("1");
                    //mockup message to make lua initiate client matching
                }
            }
            else if( CH == '2' ) {
                if( N_STATE >= N_MATCHED ) {
                    MQ.push_back("return {T='MOV', x=0, y=0}");
                    //mockup message to test gameplay protocol.
                }
            }
            process_lua();
        }
        CH = 0; //reset CH here
#if defined(WIN32) || defined(__WIN32__)
        Sleep(1);
#else   //NOT WIN32
        usleep(1000);
#endif  //WIN32
    }
    end_lua();
    return 0;
}
