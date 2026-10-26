# Toolhelp works inside the isolated test environment where WMI may be unavailable.
function Initialize-EditorProcessInspection {
 if(!('AIVoice2Validation.ProcessSnapshot' -as [type])){
  Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
namespace AIVoice2Validation {
 public sealed class ExitObserver : IDisposable {
  IntPtr handle;
  [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(uint access,bool inherit,uint pid);
  [DllImport("kernel32.dll", SetLastError=true)] static extern uint WaitForSingleObject(IntPtr handle,uint timeout);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetExitCodeProcess(IntPtr handle,out uint code);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
  public ExitObserver(int pid) {
   handle=OpenProcess(0x101000,false,(uint)pid);
   if(handle==IntPtr.Zero) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
  }
  public bool Wait(int milliseconds) {
   uint result=WaitForSingleObject(handle,(uint)milliseconds);
   if(result==0) return true;
   if(result==258) return false;
   throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
  }
  public uint ExitCode { get {uint code;if(!GetExitCodeProcess(handle,out code)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());return code;} }
  public void Dispose() {if(handle!=IntPtr.Zero){CloseHandle(handle);handle=IntPtr.Zero;}}
 }
 public static class ProcessSnapshot {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  struct Entry {
   public uint size, usage, pid;
   public UIntPtr heap;
   public uint module, threads, parent;
   public int priority;
   public uint flags;
   [MarshalAs(UnmanagedType.ByValTStr, SizeConst=260)] public string image;
  }
  [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr CreateToolhelp32Snapshot(uint flags,uint pid);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool Process32FirstW(IntPtr snapshot,ref Entry entry);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool Process32NextW(IntPtr snapshot,ref Entry entry);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
  public static uint[] Children(uint parent) {
   IntPtr snapshot=CreateToolhelp32Snapshot(2,0);
   if(snapshot==new IntPtr(-1)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
   try {
    var children=new List<uint>();
    var entry=new Entry(); entry.size=(uint)Marshal.SizeOf(typeof(Entry));
    if(!Process32FirstW(snapshot,ref entry)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    do {if(entry.parent==parent) children.Add(entry.pid);} while(Process32NextW(snapshot,ref entry));
    int error=Marshal.GetLastWin32Error();
    if(error!=18) throw new System.ComponentModel.Win32Exception(error);
    return children.ToArray();
   } finally {CloseHandle(snapshot);}
  }
 }
}
'@
 }
}
function Get-EditorChildProcess([int]$EditorPid) {
 Initialize-EditorProcessInspection
 [AIVoice2Validation.ProcessSnapshot]::Children([uint32]$EditorPid)
}
function New-EditorExitObserver([int]$EditorPid) {
 Initialize-EditorProcessInspection
 [AIVoice2Validation.ExitObserver]::new($EditorPid)
}
