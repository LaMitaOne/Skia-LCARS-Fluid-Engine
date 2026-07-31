# Skia-LCARS-Fluid-Engine
An experimental, high-performance LCARS UI rendering engine for Delphi FMX, built natively on Skia4Delphi.    
       
Could not resist to try lcars too. Its not fully original style, but still looking not bad :)    
    
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/LaMitaOne/Skia-LCARS-Fluid-Engine)    

Sample video: https://youtu.be/pv75NqcYfc0    
        

 <img width="360" height="202" alt="axul9r" src="https://github.com/user-attachments/assets/8aad1ec9-4ccd-44d2-be09-4c1c891ebd3a" />

 🚀 Features    
   
    Multi-threaded Render Loop: Update and draw logic is handled in a background thread with adaptive sleep cycles to save CPU when idle.    
    Fluid Shape Morphing: UI elements can seamlessly change their shape (e.g., from a block to a pill) by interpolating vertices at runtime.    
    Smart Offscreen Caching: Static UI elements are rendered once to an offscreen surface and cached as an ISkImage to reduce draw calls.    
    Object Pooling: Faded-out UI elements aren't destroyed; they are recycled into a pool for later use.    
    Tactical Combat Display: A fully animated radar sweep, a moving enemy AI, and functioning visual weapons (Phasers and Photon Torpedoes).    
    Dynamic Layouts: Switch between Bridge, Tactical, and Engineering layouts with smooth slide-in/out animations.    
    
📦 Contents    
    
    Sample project and executable included.    
