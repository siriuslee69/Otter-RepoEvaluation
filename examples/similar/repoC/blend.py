# Same job again, in Python.
def blend_rows(top, bottom, alpha):
    out = []
    for i in range(len(top)):
        a = top[i] * alpha
        b = bottom[i] * (1 - alpha)
        out.append(round(a + b))
    if len(out) == 0:
        return []
    return out
