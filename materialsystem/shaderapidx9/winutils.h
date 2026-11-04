//========= Copyright Valve Corporation, All rights reserved. ============//
//
//
//
//==================================================================================================
#ifndef WINUTILS_H
#define WINUTILS_H

#include "togl/rendermechanism.h" // for win types

#if defined( DXVK )
	// DXVK-native: the D3D9 path calls a few Win32 window functions; HWND is the
	// SDL_Window* (implemented with SDL in winutils.cpp). MEMORYSTATUS comes from DXVK.

	void Sleep( unsigned int ms );
	BOOL IsIconic( VD3DHWND hWnd );
	BOOL GetClientRect( VD3DHWND hWnd, RECT *pRect );
	BOOL ClientToScreen( VD3DHWND hWnd, LPPOINT pPoint );
	void* GetCurrentThread();
	void SetThreadAffinityMask( void *hThread, int nMask );
	void GlobalMemoryStatus( MEMORYSTATUS *pOut );
#elif !defined(_WIN32)

	void Sleep( unsigned int ms );
	bool IsIconic( VD3DHWND hWnd );
	BOOL ClientToScreen( VD3DHWND hWnd, LPPOINT pPoint );
	void* GetCurrentThread();
	void SetThreadAffinityMask( void *hThread, int nMask );
	void GlobalMemoryStatus( MEMORYSTATUS *pOut );
#endif

#endif // WINUTILS_H
