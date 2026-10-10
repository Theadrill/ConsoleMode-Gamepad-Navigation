#ifndef GLUEPAD_GLOG_H
#define GLUEPAD_GLOG_H

/* Log duplo: OutputDebugStringA + %TEMP%\gluepad_f1.log. ASCII puro. */
void GluePad_LogRaw(const char *line);

/* Serializa as escritas (WndProc da main thread + thread de poll). */
void GluePad_LogInit(void);
void GluePad_LogShutdown(void);

#endif
