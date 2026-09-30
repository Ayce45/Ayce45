import Toybox.Lang;
import Toybox.WatchUi;

// Navigation entre les ecrans de seance.
module Flow {

    // Affiche l'ecran de la serie courante (ou le resume si la seance est finie).
    function showCurrent(transition as SlideType, push as Boolean) as Void {
        var view;
        var delegate;
        if (Model.exIndex >= Model.exerciseCount()) {
            view = new SummaryView();
            delegate = new SummaryDelegate(view);
        } else {
            var ex = Model.currentExercise();
            var kind = Model.exerciseKind(ex);
            if (kind.equals("strength")) {
                view = new SetView();
                delegate = new SetDelegate(view);
            } else {
                view = new TimedSetView();
                delegate = new TimedSetDelegate(view);
            }
        }
        if (push) {
            WatchUi.pushView(view, delegate, transition);
        } else {
            WatchUi.switchToView(view, delegate, transition);
        }
    }

    // Apres validation d'une serie : repos si prevu, sinon serie suivante.
    function afterSet(finished as Boolean, restSeconds as Number) as Void {
        if (finished) {
            var sv = new SummaryView();
            WatchUi.switchToView(sv, new SummaryDelegate(sv), WatchUi.SLIDE_LEFT);
            return;
        }
        if (restSeconds > 1 && Model.autoStartRest) {
            var rv = new RestView(restSeconds);
            WatchUi.switchToView(rv, new RestDelegate(rv), WatchUi.SLIDE_LEFT);
        } else {
            showCurrent(WatchUi.SLIDE_LEFT, false);
        }
    }

    function showExerciseList() as Void {
        var menu = new WatchUi.Menu2({ :title => WatchUi.loadResource(Rez.Strings.Exercises) as String });
        var exs = Model.exercises();
        for (var i = 0; i < exs.size(); i++) {
            var ex = exs[i] as Dictionary;
            var sets = Model.setsOf(ex);
            var sub = sets.size() + " x ";
            if (sets.size() > 0) {
                var s0 = sets[0] as Dictionary;
                if (s0.hasKey("reps")) {
                    sub += s0["reps"].toString();
                    if (s0.hasKey("weight_kg")) { sub += " @ " + Ui.fmtKg(Model.num(s0, "weight_kg", 0)) + " kg"; }
                } else if (s0.hasKey("duration_s")) {
                    sub += s0["duration_s"].toString() + " s";
                }
            }
            var label = (i + 1) + ". " + Model.exerciseTitle(ex);
            if (Model.exerciseDone(i)) { label = "[x] " + label; }
            else if (Model.machineDone(ex)) { label = "[M] " + label; }
            else if (i == Model.exIndex && Model.inProgress) { label = "> " + label; }
            menu.addItem(new WatchUi.MenuItem(label, sub, i, null));
        }
        WatchUi.pushView(menu, new ExerciseListDelegate(), WatchUi.SLIDE_UP);
    }

    function showWorkoutMenu() as Void {
        var menu = new WatchUi.Menu2({ :title => Model.exerciseTitle(Model.currentExercise()) });
        menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.Undo) as String, null, :undo, null));
        menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.SkipExercise) as String, null, :skipEx, null));
        menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.Exercises) as String, null, :list, null));
        menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.Finish) as String, null, :finish, null));
        menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.Discard) as String, null, :discard, null));
        WatchUi.pushView(menu, new WorkoutMenuDelegate(), WatchUi.SLIDE_UP);
    }
}

class ExerciseListDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as MenuItem) as Void {
        var id = item.getId();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        if (id instanceof Number && Model.inProgress) {
            Model.jumpTo(id as Number);
            Flow.showCurrent(WatchUi.SLIDE_LEFT, false);
        }
    }
}

class WorkoutMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as MenuItem) as Void {
        var id = item.getId();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        if (id == :undo) {
            Model.undoLast();
            Flow.showCurrent(WatchUi.SLIDE_RIGHT, false);
        } else if (id == :skipEx) {
            var finished = Model.skipExercise();
            Flow.afterSet(finished, 0);
        } else if (id == :list) {
            Flow.showExerciseList();
        } else if (id == :finish) {
            var sv = new SummaryView();
            WatchUi.switchToView(sv, new SummaryDelegate(sv), WatchUi.SLIDE_LEFT);
        } else if (id == :discard) {
            Recording.discard();
            Model.resetProgress();
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
    }
}
