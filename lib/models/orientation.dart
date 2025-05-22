enum Orientation {
  landscape, portrait, auto;

  static Orientation next(Orientation state) {
    int nextIndex = (state.index + 1) % Orientation.values.length;
    return Orientation.values[nextIndex];
  }
}