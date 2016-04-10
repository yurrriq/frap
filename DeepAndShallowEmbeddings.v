(** Formal Reasoning About Programs <http://adam.chlipala.net/frap/>
  * Chapter 11: Deep and Shallow Embeddings
  * Author: Adam Chlipala
  * License: https://creativecommons.org/licenses/by-nc-nd/4.0/ *)

Require Import Frap.

Set Implicit Arguments.

(** * Shared notations and definitions *)

Notation "m $! k" := (match m $? k with Some n => n | None => O end) (at level 30).
Definition heap := fmap nat nat.
Definition assertion := heap -> Prop.

Hint Extern 1 (_ <= _) => linear_arithmetic.
Hint Extern 1 (@eq nat _ _) => linear_arithmetic.

Example h0 : heap := $0 $+ (0, 2) $+ (1, 1) $+ (2, 8) $+ (3, 6).

Hint Rewrite max_l max_r using linear_arithmetic.


(** * Shallow embedding of a language very similar to the one we used last chapter *)

Module Shallow.
  Definition cmd result := heap -> heap * result.

  Definition hoare_triple (P : assertion) {result} (c : cmd result) (Q : result -> assertion) :=
    forall h, P h
              -> let (h', r) := c h in
                 Q r h'.

  Notation "{{ h ~> P }} c {{ r & h' ~> Q }}" :=
    (hoare_triple (fun h => P) c (fun r h' => Q)) (at level 90, c at next level).

  Theorem consequence : forall P {result} (c : cmd result) Q
                               (P' : assertion) (Q' : _ -> assertion),
      hoare_triple P c Q
      -> (forall h, P' h -> P h)
      -> (forall r h, Q r h -> Q' r h)
      -> hoare_triple P' c Q'.
  Proof.
    unfold hoare_triple; simplify.
    specialize (H h).
    specialize (H0 h).
    cases (c h).
    auto.
  Qed.

  Fixpoint array_max (i acc : nat) : cmd nat :=
    fun h =>
      match i with
      | O => (h, acc)
      | S i' =>
        let h_i' := h $! i' in
        array_max i' (max h_i' acc) h
      end.

  Lemma array_max_ok' : forall len i acc,
    {{ h ~> forall j, i <= j < len -> h $! j <= acc }}
      array_max i acc
    {{ r&h ~> forall j, j < len -> h $! j <= r }}.
  Proof.
    induct i; unfold hoare_triple in *; simplify; propositional; auto.

    specialize (IHi (max (h $! i) acc) h); propositional.
    cases (array_max i (max (h $! i) acc)); simplify; propositional; subst.
    apply IHi; auto.
    simplify.
    cases (j0 ==n i); subst; auto.
    assert (h $! j0 <= acc) by auto.
    linear_arithmetic.
  Qed.

  Theorem array_max_ok : forall len,
    {{ _ ~> True }}
      array_max len 0
    {{ r&h ~> forall i, i < len -> h $! i <= r }}.
  Proof.
    simplify.
    eapply consequence.
    apply array_max_ok' with (len := len).

    simplify.
    linear_arithmetic.

    auto.
  Qed.

  Example run_array_max0 : array_max 4 0 h0 = (h0, 8).
  Proof.
    unfold h0.
    simplify.
    reflexivity.
  Qed.

  Fixpoint increment_all (i : nat) : cmd unit :=
    fun h =>
      match i with
      | O => (h, tt)
      | S i' => increment_all i' (h $+ (i', S (h $! i')))
      end.

  Lemma increment_all_ok' : forall len h0 i,
    {{ h ~> (forall j, j < i -> h $! j = h0 $! j)
       /\ (forall j, i <= j < len -> h $! j = S (h0 $! j)) }}
      increment_all i
    {{ _&h ~> forall j, j < len -> h $! j = S (h0 $! j) }}.
  Proof.
    induct i; unfold hoare_triple in *; simplify; propositional; auto.

    specialize (IHi (h $+ (i, S (h $! i)))); propositional.
    cases (increment_all i (h $+ (i, S (h $! i)))); simplify; propositional; subst.
    apply H; simplify; auto.

    cases (j0 ==n i); subst; auto.
    simplify; auto.
    simplify; auto.
  Qed.

  Theorem increment_all_ok : forall len h0,
    {{ h ~> h = h0 }}
      increment_all len
    {{ _&h ~> forall j, j < len -> h $! j = S (h0 $! j) }}.
  Proof.
    simplify.
    eapply consequence.
    apply increment_all_ok' with (len := len).

    simplify; subst; propositional.
    linear_arithmetic.

    simplify.
    auto.
  Qed.

  Example run_increment_all0 : increment_all 4 h0 = ($0 $+ (0, 3) $+ (1, 2) $+ (2, 9) $+ (3, 7), tt).
  Proof.
    unfold h0.
    simplify.
    f_equal.
    maps_equal.
  Qed.
End Shallow.


(** * A basic deep embedding *)

Module Deep.
  Inductive cmd : Set -> Type :=
  | Return {result : Set} (r : result) : cmd result
  | Bind {result result'} (c1 : cmd result') (c2 : result' -> cmd result) : cmd result
  | Read (a : nat) : cmd nat
  | Write (a v : nat) : cmd unit.

  Notation "x <- c1 ; c2" := (Bind c1 (fun x => c2)) (right associativity, at level 80).

  Fixpoint array_max (i acc : nat) : cmd nat :=
    match i with
    | O => Return acc
    | S i' =>
      h_i' <- Read i';
      array_max i' (max h_i' acc)
    end.

  Fixpoint increment_all (i : nat) : cmd unit :=
    match i with
    | O => Return tt
    | S i' =>
      v <- Read i';
      _ <- Write i' (S v); 
      increment_all i'
    end.

  Fixpoint interp {result} (c : cmd result) (h : heap) : heap * result :=
    match c with
    | Return r => (h, r)
    | Bind c1 c2 =>
      let (h', r) := interp c1 h in
      interp (c2 r) h'
    | Read a => (h, h $! a)
    | Write a v => (h $+ (a, v), tt)
    end.

  Example run_array_max0 : interp (array_max 4 0) h0 = (h0, 8).
  Proof.
    unfold h0.
    simplify.
    reflexivity.
  Qed.

  Example run_increment_all0 : interp (increment_all 4) h0 = ($0 $+ (0, 3) $+ (1, 2) $+ (2, 9) $+ (3, 7), tt).
  Proof.
    unfold h0.
    simplify.
    f_equal.
    maps_equal.
  Qed.

  Inductive hoare_triple : assertion -> forall {result}, cmd result -> (result -> assertion) -> Prop :=
  | HtReturn : forall P {result : Set} (v : result),
      hoare_triple P (Return v) (fun r h => P h /\ r = v)
  | HtBind : forall P {result' result} (c1 : cmd result') (c2 : result' -> cmd result) Q R,
      hoare_triple P c1 Q
      -> (forall r, hoare_triple (Q r) (c2 r) R)
      -> hoare_triple P (Bind c1 c2) R
  | HtRead : forall P a,
      hoare_triple P (Read a) (fun r h => P h /\ r = h $! a)
  | HtWrite : forall P a v,
      hoare_triple P (Write a v) (fun _ h => exists h', P h' /\ h = h' $+ (a, v))
  | HtConsequence : forall {result} (c : cmd result) P Q (P' : assertion) (Q' : _ -> assertion),
      hoare_triple P c Q
      -> (forall h, P' h -> P h)
      -> (forall r h, Q r h -> Q' r h)
      -> hoare_triple P' c Q'.

  Lemma HtStrengthen : forall {result} (c : cmd result) P Q (Q' : _ -> assertion),
      hoare_triple P c Q
      -> (forall r h, Q r h -> Q' r h)
      -> hoare_triple P c Q'.
  Proof.
    simplify.
    eapply HtConsequence; eauto.
  Qed.

  Notation "{{ h ~> P }} c {{ r & h' ~> Q }}" :=
    (hoare_triple (fun h => P) c (fun r h' => Q)) (at level 90, c at next level).

  Lemma array_max_ok' : forall len i acc,
    {{ h ~> forall j, i <= j < len -> h $! j <= acc }}
      array_max i acc
    {{ r&h ~> forall j, j < len -> h $! j <= r }}.
  Proof.
    induct i; simplify.

    eapply HtStrengthen.
    econstructor.
    simplify.
    propositional.
    subst.
    auto.

    econstructor.
    constructor.
    simplify.
    eapply HtConsequence.
    apply IHi.
    simplify; propositional.
    subst.
    cases (j ==n i); subst; auto.
    assert (h $! j <= acc) by auto.
    linear_arithmetic.

    simplify; auto.
  Qed.

  Theorem array_max_ok : forall len,
    {{ _ ~> True }}
      array_max len 0
    {{ r&h ~> forall i, i < len -> h $! i <= r }}.
  Proof.
    simplify.
    eapply HtConsequence.
    apply array_max_ok' with (len := len).

    simplify.
    linear_arithmetic.

    auto.
  Qed.

  Lemma increment_all_ok' : forall len h0 i,
    {{ h ~> (forall j, j < i -> h $! j = h0 $! j)
       /\ (forall j, i <= j < len -> h $! j = S (h0 $! j)) }}
      increment_all i
    {{ _&h ~> forall j, j < len -> h $! j = S (h0 $! j) }}.
  Proof.
    induct i; simplify; propositional.

    eapply HtStrengthen.
    econstructor.
    simplify.
    propositional.
    auto.

    econstructor.
    econstructor.
    simplify.
    econstructor.
    econstructor.
    simplify.
    eapply HtConsequence.
    apply IHi.
    simplify.
    invert H; propositional; subst.
    simplify.
    auto.

    cases (j ==n i); subst; auto.
    simplify; auto.
    simplify; auto.

    simplify; auto.
  Qed.

  Theorem increment_all_ok : forall len h0,
    {{ h ~> h = h0 }}
      increment_all len
    {{ _&h ~> forall j, j < len -> h $! j = S (h0 $! j) }}.
  Proof.
    simplify.
    eapply HtConsequence.
    apply increment_all_ok' with (len := len).

    simplify; subst; propositional.
    linear_arithmetic.

    simplify.
    auto.
  Qed.

  Theorem hoare_triple_sound : forall P {result} (c : cmd result) Q,
      hoare_triple P c Q
      -> forall h, P h
                   -> let (h', r) := interp c h in
                      Q r h'.
  Proof.
    induct 1; simplify; propositional; eauto.

    specialize (IHhoare_triple h).
    cases (interp c1 h).
    apply H1; eauto.

    specialize (IHhoare_triple h).
    cases (interp c h).
    eauto.
  Qed.

  Extraction "Deep.ml" array_max increment_all.
End Deep.


(** * A slightly fancier deep embedding, adding unbounded loops *)

Module Deeper.
  Inductive loop_outcome acc :=
  | Done (a : acc)
  | Again (a : acc).

  Inductive cmd : Set -> Type :=
  | Return {result : Set} (r : result) : cmd result
  | Bind {result result'} (c1 : cmd result') (c2 : result' -> cmd result) : cmd result
  | Read (a : nat) : cmd nat
  | Write (a v : nat) : cmd unit
  | Loop {acc : Set} (init : acc) (body : acc -> cmd (loop_outcome acc)) : cmd acc.

  Notation "x <- c1 ; c2" := (Bind c1 (fun x => c2)) (right associativity, at level 80).
  Notation "'for' x := i 'loop' c1 'done'" := (Loop i (fun x => c1)) (right associativity, at level 80).

  Definition index_of (needle : nat) : cmd nat :=
    for i := 0 loop
      h_i <- Read i;
      if h_i ==n needle then
        Return (Done i)
      else
        Return (Again (S i))
    done.

  Inductive stepResult (result : Set) :=
  | Answer (r : result)
  | Stepped (h : heap) (c : cmd result). 

  Fixpoint step {result} (c : cmd result) (h : heap) : stepResult result :=
    match c with
    | Return r => Answer r
    | Bind c1 c2 =>
      match step c1 h with
      | Answer r => Stepped h (c2 r)
      | Stepped h' c1' => Stepped h' (Bind c1' c2)
      end
    | Read a => Answer (h $! a)
    | Write a v => Stepped (h $+ (a, v)) (Return tt)
    | Loop init body =>
      Stepped h (r <- body init;
                 match r with
                 | Done r' => Return r'
                 | Again r' => Loop r' body
                 end)
    end.

  Fixpoint multiStep {result} (c : cmd result) (h : heap) (n : nat) : stepResult result :=
    match n with
    | O => Stepped h c
    | S n' => match step c h with
              | Answer r => Answer r
              | Stepped h' c' => multiStep c' h' n'
              end
    end.

  Example run_index_of : multiStep (index_of 6) h0 20 = Answer 3.
  Proof.
    unfold h0.
    simplify.
    reflexivity.
  Qed.

  Inductive hoare_triple : assertion -> forall {result}, cmd result -> (result -> assertion) -> Prop :=
  | HtReturn : forall P {result : Set} (v : result),
      hoare_triple P (Return v) (fun r h => P h /\ r = v)
  | HtBind : forall P {result' result} (c1 : cmd result') (c2 : result' -> cmd result) Q R,
      hoare_triple P c1 Q
      -> (forall r, hoare_triple (Q r) (c2 r) R)
      -> hoare_triple P (Bind c1 c2) R
  | HtRead : forall P a,
      hoare_triple P (Read a) (fun r h => P h /\ r = h $! a)
  | HtWrite : forall P a v,
      hoare_triple P (Write a v) (fun _ h => exists h', P h' /\ h = h' $+ (a, v))
  | HtConsequence : forall {result} (c : cmd result) P Q (P' : assertion) (Q' : _ -> assertion),
      hoare_triple P c Q
      -> (forall h, P' h -> P h)
      -> (forall r h, Q r h -> Q' r h)
      -> hoare_triple P' c Q'

  | HtLoop : forall {acc : Set} (init : acc) (body : acc -> cmd (loop_outcome acc)) I,
      (forall acc, hoare_triple (I (Again acc)) (body acc) I)
      -> hoare_triple (I (Again init)) (Loop init body) (fun r h => I (Done r) h).

  Notation "{{ h ~> P }} c {{ r & h' ~> Q }}" :=
    (hoare_triple (fun h => P) c (fun r h' => Q)) (at level 90, c at next level).

  Lemma HtStrengthen : forall {result} (c : cmd result) P Q (Q' : _ -> assertion),
      hoare_triple P c Q
      -> (forall r h, Q r h -> Q' r h)
      -> hoare_triple P c Q'.
  Proof.
    simplify.
    eapply HtConsequence; eauto.
  Qed.

  Lemma HtWeaken : forall {result} (c : cmd result) P Q (P' : assertion),
      hoare_triple P c Q
      -> (forall h, P' h -> P h)
      -> hoare_triple P' c Q.
  Proof.
    simplify.
    eapply HtConsequence; eauto.
  Qed.

  Theorem index_of_ok : forall hinit needle,
    {{ h ~> h = hinit }}
      index_of needle
    {{ r&h ~> h = hinit
         /\ hinit $! r = needle
         /\ forall i, i < r -> hinit $! i <> needle }}.
  Proof.
    unfold index_of.
    simplify.
    eapply HtConsequence.
    apply HtLoop with (I := fun r h => h = hinit
                                       /\ match r with
                                          | Done r' => hinit $! r' = needle
                                                       /\ forall i, i < r' -> hinit $! i <> needle
                                          | Again r' => forall i, i < r' -> hinit $! i <> needle
                                          end); simplify.

    econstructor.
    econstructor.

    simplify.
    cases (r ==n needle); subst.
    eapply HtStrengthen.
    econstructor.
    simplify; propositional; subst.
    auto.

    eapply HtStrengthen.
    econstructor.
    simplify.
    propositional; subst.
    simplify.
    cases (i ==n acc); subst; auto.
    apply H3 with (i0 := i); auto.

    simplify.
    propositional.
    linear_arithmetic.

    simplify.
    propositional.
  Qed.

  Definition trsys_of {result} (c : cmd result) (h : heap) := {|
    Initial := {(c, h)};
    Step := fun p1 p2 => step (fst p1) (snd p1) = Stepped (snd p2) (fst p2)
  |}.

  Lemma invert_Return : forall {result : Set} (r : result) P Q,
    hoare_triple P (Return r) Q
    -> forall h, P h -> Q r h.
  Proof.
    induct 1; propositional; eauto.
  Qed.

  Lemma invert_Bind : forall {result' result} (c1 : cmd result') (c2 : result' -> cmd result) P Q,
    hoare_triple P (Bind c1 c2) Q
    -> exists R, hoare_triple P c1 R
                 /\ forall r, hoare_triple (R r) (c2 r) Q.
  Proof.
    induct 1; propositional; eauto.

    invert IHhoare_triple; propositional.
    eexists; propositional.
    eapply HtWeaken.
    eassumption.
    auto.
    eapply HtStrengthen.
    apply H4.
    auto.
  Qed.

  Lemma unit_not_nat : unit = nat -> False.
  Proof.
    simplify.
    assert (exists x : unit, forall y : unit, x = y).
    exists tt; simplify.
    cases y; reflexivity.
    rewrite H in H0.
    invert H0.
    specialize (H1 (S x)).
    linear_arithmetic.
  Qed.

  Lemma invert_Read : forall a P Q,
    hoare_triple P (Read a) Q
    -> forall h, P h -> Q (h $! a) h.
  Proof.
    induct 1; propositional; eauto.
    apply unit_not_nat in x0.
    propositional.
  Qed.

  Lemma invert_Write : forall a v P Q,
    hoare_triple P (Write a v) Q
    -> forall h, P h -> Q tt (h $+ (a, v)).
  Proof.
    induct 1; propositional; eauto.
    symmetry in x0.
    apply unit_not_nat in x0.
    propositional.
  Qed.

  Lemma invert_Loop : forall {acc : Set} (init : acc) (body : acc -> cmd (loop_outcome acc)) P Q,
      hoare_triple P (Loop init body) Q
      -> exists I, (forall acc, hoare_triple (I (Again acc)) (body acc) I)
                   /\ (forall h, P h -> I (Again init) h)
                   /\ (forall r h, I (Done r) h -> Q r h).
  Proof.
    induct 1; propositional; eauto.

    invert IHhoare_triple; propositional.
    exists x; propositional; eauto.
  Qed.

  Lemma step_sound : forall {result} (c : cmd result) h Q,
      hoare_triple (fun h' => h' = h) c Q
      -> match step c h with
         | Answer r => Q r h
         | Stepped h' c' => hoare_triple (fun h'' => h'' = h') c' Q
         end.
  Proof.
    induct c; simplify; propositional.

    eapply invert_Return.
    eauto.
    simplify; auto.

    apply invert_Bind in H0.
    invert H0; propositional.
    apply IHc in H0.
    cases (step c h); auto.
    econstructor.
    apply H2.
    equality.
    auto.
    econstructor; eauto.

    eapply invert_Read; eauto.
    simplify; auto.

    eapply HtStrengthen.
    econstructor.
    simplify; propositional; subst.
    eapply invert_Write; eauto.
    simplify; auto.

    apply invert_Loop in H0.
    invert H0; propositional.
    econstructor.
    eapply HtWeaken.
    apply H0.
    equality.
    simplify.
    cases r.
    eapply HtStrengthen.
    econstructor.
    simplify.
    propositional; subst; eauto.
    eapply HtStrengthen.
    eapply HtLoop.
    auto.
    simplify.
    eauto.
  Qed.

  Lemma hoare_triple_sound' : forall P {result} (c : cmd result) Q,
      hoare_triple P c Q
      -> forall h, P h
                   -> invariantFor (trsys_of c h)
                                   (fun p => hoare_triple (fun h => h = snd p)
                                                          (fst p)
                                                          Q).
  Proof.
    simplify.

    apply invariant_induction; simplify.

    propositional; subst; simplify.
    eapply HtConsequence.
    eassumption.
    equality.
    auto.

    eapply step_sound in H1.
    rewrite H2 in H1.
    auto.
  Qed.

  Theorem hoare_triple_sound : forall P {result} (c : cmd result) Q,
      hoare_triple P c Q
      -> forall h, P h
                   -> invariantFor (trsys_of c h)
                                   (fun p => forall r, fst p = Return r
                                                       -> Q r (snd p)).
  Proof.
    simplify.

    eapply invariant_weaken.
    eapply hoare_triple_sound'; eauto.
    simplify.
    rewrite H2 in H1.
    eapply invert_Return; eauto.
    simplify; auto.
  Qed.

  Extraction "Deeper.ml" index_of.
End Deeper.
