//========= Copyright Valve Corporation, All rights reserved. ============//
//
// winutils.cpp
//
//===========================================================================//

#include "winutils.h"

#ifndef _WIN32

#include "appframework/ilaunchermgr.h"
#include <ctype.h>
#ifdef DXVK
#include <SDL.h>
#endif

// LINUX path taken from //Steam/main/src/tier0/platform_posix.cpp - Returns installed RAM in MB. 
static unsigned long GetInstalledRAM()
{
	unsigned long ulTotalRamMB = 2047;

#ifdef LINUX
	char rgchLine[256];
	FILE *fpMemInfo = fopen( "/proc/meminfo", "r" );
	if ( !fpMemInfo )
		return ulTotalRamMB;

	const char *pszSearchString = "MemTotal:";
	const uint cchSearchString = strlen( pszSearchString );
	while ( fgets( rgchLine, sizeof(rgchLine), fpMemInfo ) )
	{
		if ( !strncasecmp( pszSearchString, rgchLine, cchSearchString ) )
		{
			char *pszVal = rgchLine+cchSearchString;
			while( isspace(*pszVal) )
				++pszVal;
			ulTotalRamMB = atol( pszVal ) / 1024; // go from kB to MB
			break;
		}
	}
	fclose( fpMemInfo );
#endif

	// 128 Gb limit for now (should future proof us for a while)
	ulTotalRamMB = MIN( ulTotalRamMB, 1024 * 128 );
	return ulTotalRamMB;
}

void GlobalMemoryStatus( MEMORYSTATUS *pOut )
{
	unsigned long nInstalledRamInMB = GetInstalledRAM();

	// For safety assume at least 128MB
	nInstalledRamInMB = MAX( nInstalledRamInMB, 128 );

	uint64 ulTotalRam = static_cast<uint64>( nInstalledRamInMB ) * ( 1024 * 1024 );
	ulTotalRam = MIN( ulTotalRam, 0xFFFFFFFF );
	
	pOut->dwTotalPhys = static_cast<SIZE_T>( ulTotalRam );
}

#ifdef DXVK
// DXVK-native: HWND is the SDL_Window*

void Sleep( unsigned int ms )
{
	ThreadSleep( ms );
}

BOOL IsIconic( VD3DHWND hWnd )
{
	return hWnd && ( SDL_GetWindowFlags( (SDL_Window *)hWnd ) & SDL_WINDOW_MINIMIZED ) ? TRUE : FALSE;
}

BOOL GetClientRect( VD3DHWND hWnd, RECT *pRect )
{
	int w = 0, h = 0;
	if ( hWnd )
		SDL_GetWindowSize( (SDL_Window *)hWnd, &w, &h );
	pRect->left = pRect->top = 0;
	pRect->right = w;
	pRect->bottom = h;
	return hWnd != NULL;
}

BOOL ClientToScreen( VD3DHWND hWnd, LPPOINT pPoint )
{
	int x = 0, y = 0;
	if ( hWnd )
		SDL_GetWindowPosition( (SDL_Window *)hWnd, &x, &y );
	pPoint->x += x;
	pPoint->y += y;
	return TRUE;
}

void* GetCurrentThread()
{
	return 0;
}

void SetThreadAffinityMask( void *hThread, int nMask )
{
}

#else

void Sleep( unsigned int ms )
{
	DebuggerBreak();
	ThreadSleep( ms );
}

bool IsIconic( VD3DHWND hWnd )
{
	// FIXME for now just act non-minimized all the time
	//DebuggerBreak();
	return false;
}

BOOL ClientToScreen( VD3DHWND hWnd, LPPOINT pPoint )
{
	DebuggerBreak();
	return true;
}

void* GetCurrentThread()
{
	DebuggerBreak();
	return 0;
}

void SetThreadAffinityMask( void *hThread, int nMask )
{
	DebuggerBreak();
}

bool GUID::operator==( const struct _GUID &other ) const
{
	DebuggerBreak();
	return memcmp( this, &other, sizeof( GUID ) ) == 0;
}
#endif // DXVK
#endif
