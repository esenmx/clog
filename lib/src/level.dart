part of dlog;

enum Level implements Comparable<Level> {
  trace,
  debug,
  info,
  warn,
  error,
  wtf,
  off;

  bool operator <(Level other) => index < other.index;

  bool operator <=(Level other) => index <= other.index;

  bool operator >(Level other) => index > other.index;

  bool operator >=(Level other) => index >= other.index;

  @override
  int compareTo(Level other) => index - other.index;
}
