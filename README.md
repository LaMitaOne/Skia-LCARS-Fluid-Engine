# Skia-LCARS-Fluid-Engine
An experimental, high-performance LCARS UI rendering engine for Delphi FMX, built natively on Skia4Delphi.    

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/LaMitaOne/Skia-LCARS-Fluid-Engine)    

   
<img width="1233" height="687" alt="Unbenannt" src="https://github.com/user-attachments/assets/67d82d64-0d35-4677-abcb-eb44c7d734ae" />
    
 🚀 Features    
   
    Multi-threaded Render Loop: Update and draw logic is handled in a background thread with adaptive sleep cycles to save CPU when idle.    
    Fluid Shape Morphing: UI elements can seamlessly change their shape (e.g., from a block to a pill) by interpolating vertices at runtime.    
    Smart Offscreen Caching: Static UI elements are rendered once to an offscreen surface and cached as an ISkImage to reduce draw calls.    
    Object Pooling: Faded-out UI elements aren't destroyed; they are recycled into a pool for later use.    
    Tactical Combat Display: A fully animated radar sweep, a moving enemy AI, and functioning visual weapons (Phasers and Photon Torpedoes).    
    Dynamic Layouts: Switch between Bridge, Tactical, and Engineering layouts with smooth slide-in/out animations.    
    
📦 Contents    
    
    Sample project and executable included.    
