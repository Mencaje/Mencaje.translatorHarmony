export enum HomeTranslatePlanKind {
  SINGLE = 0,
  DUAL = 1
}

/** 与 Android MainActivity.HomeTranslatePlan 一致 */
export class HomeTranslatePlan {
  kind: HomeTranslatePlanKind = HomeTranslatePlanKind.SINGLE;
  sourceIso: string = '';
  targetIso: string = '';
  fromIso: string = '';
  targetFirstIso: string = '';
  targetSecondIso: string = '';
}

export class HomeTranslatePlanner {
  static build(fromIso: string, prefSourceIso: string, prefTargetIso: string): HomeTranslatePlan | null {
    if (prefSourceIso === prefTargetIso) {
      return null;
    }
    if (fromIso === prefSourceIso) {
      const p = new HomeTranslatePlan();
      p.kind = HomeTranslatePlanKind.SINGLE;
      p.sourceIso = prefSourceIso;
      p.targetIso = prefTargetIso;
      return p;
    }
    if (fromIso === prefTargetIso) {
      const p = new HomeTranslatePlan();
      p.kind = HomeTranslatePlanKind.SINGLE;
      p.sourceIso = prefTargetIso;
      p.targetIso = prefSourceIso;
      return p;
    }
    const d = new HomeTranslatePlan();
    d.kind = HomeTranslatePlanKind.DUAL;
    d.fromIso = fromIso;
    d.targetFirstIso = prefSourceIso;
    d.targetSecondIso = prefTargetIso;
    return d;
  }
}
