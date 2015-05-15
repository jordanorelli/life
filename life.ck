13475 => int monomeIn;
16426 => int monomeOut;
"/manager" => string monomePrefix;
"127.0.0.1" => string monomeHost;

OscRecv recv;
monomeIn => recv.port;
recv.listen();

fun float[][] toneGrid(int width, int height, int columnStep, int rowStep, float baseFreq, float octaveSteps) {
    float tones[width][height];
    Math.pow(2, 1.0/ octaveSteps $ float) => float toneStep;
    for(0 => int row; row < height; row++) {
        baseFreq * Math.pow(toneStep, row * rowStep) => float rowBase;
        for(0 => int col; col < width; col++) {
            rowBase * Math.pow(toneStep, col * columnStep)
                => tones[col][row];
        }
    }
    return tones;
}

class Monome {

    string prefix;
    string hostname;
    OscRecv recv;
    OscSend snd;

    // PROTECTED FINAL
    //
    // Initialization:  sets up the monome and listens for incoming messages.
    fun void init(string _prefix, string _hostname, int in, int out) {
        preInit();
        _prefix => prefix;
        _hostname => hostname;

        OscSend m;
        m.setHost(hostname, out);
        m @=> snd;

        in => recv.port;
        recv.listen();

        spork ~ keyListener();
        spork ~ tiltListener();
        all(0);
        postInit();
    }

    // PUBLIC
    //
    // preInit is called before the init cycle finishes.
    //
    fun void preInit() {}

    // PUBLIC
    //
    // postInit is called after the init cycle finishes.
    //
    fun void postInit() {}

    // PUBLIC
    //
    // key is called once for every time a key is pressed on the Monome.
    // Override this method in a child class to define how to handle key
    // presses from the monome.
    fun void key(int x, int y, int z) {
        <<< prefix, "key", x, y, z >>>;
    }

    // PUBLIC
    //
    // position change on tilt sensor n, integer (8-bit) values (x, y, z).
    // This method is called once for each OSC message received from the monome
    // with regards to its tilt.
    fun void tilt(int n, int x, int y, int z) {
        <<< prefix, "tilt", n, x, y, z >>>;
    }

    // PRIVATE
    //
    // key press handler.  This is invoked automatically by the Monome
    // constructor, and should not be called.  This method starts an infinite
    // loop and listens for incoming osc messages from the monome.  When
    // messages are received, the monome object's "key" method is called.
    //
    fun void keyListener() {
        recv.event(prefix+"/grid/key", "iii") @=> OscEvent e;
        while(true) {
            e => now;
            while(e.nextMsg() != 0) {
                e.getInt() => int x;
                e.getInt() => int y;
                e.getInt() => int z;
                key(x, y, z);
            }
        }
    }

    // PRIVATE
    //
    // tilt sensor handler.  This is invoked automatically by the Monome
    // constructor, and should not be called.  This method starts an infinite
    // loop and listens for incoming osc messages from the monome.  When
    // messages are received, the monome object's "tilt" method is called.
    //
    fun void tiltListener() {
        recv.event(prefix+"/tilt", "iiii") @=> OscEvent e;
        while(true) {
            e => now;
            while(e.nextMsg() != 0) {
                e.getInt() => int n;
                e.getInt() => int x;
                e.getInt() => int y;
                e.getInt() => int z;
                tilt(n, x, y, z);
            }
        }
    }

    // PROTECTED FINAL
    //
    // set led at (x,y) to state s (0 or 1).
    //
    fun void set(int x, int y, int s) {
        snd.startMsg(prefix+"/grid/led/set", "iii");
        snd.addInt(x);
        snd.addInt(y);
        snd.addInt(s);
        me.yield();
    }

    // PROTECTED FINAL
    //
    // set all leds to state s (0 or 1).
    //
    fun void all(int i) {
        snd.startMsg(prefix+"/grid/led/all", "i");
        snd.addInt(i);
        me.yield();
    }
}

class Life extends Monome {
    float tones[8][8];
    int lifeState[8][8];
    int nextLifeState[8][8];
    100::ms => dur genStep;
    false => int running;

    fun void preInit() {
        toneGrid(8, 8, 1, 6, 220, 12) @=> tones;
    }

    fun void postInit() {
        all(0);
        spork ~ live();
    }

    fun void live() {
        true => running;
        while(running) {
            step();
            genStep => now;
        }
    }

    fun void pause() {
        <<< "pause!" >>>;
        if(running) {
            false => running;
        } else {
            spork ~ live();
        }
    }

    fun void step() {
        for(0 => int i; i < 8; i++) {
            for(0 => int j; j < 8; j++) {
                step(i, j);
            }
        }

        for(0 => int i; i < 8; i++) {
            for(0 => int j; j < 8; j++) {
                if(nextLifeState[i][j] != lifeState[i][j]) {
                    set(i, j, nextLifeState[i][j]);
                    spork ~ play(i, j);
                }
                nextLifeState[i][j] => lifeState[i][j];
            }
        }
    }

    fun void play(int x, int y) {
        SinOsc s => ADSR env => dac;
        tones[x][y] => s.freq;
        env.set(20::ms, 100::ms, 0.7, 20::ms);
        env.keyOn();
        40::ms => now;
        env.keyOff();
        40::ms => now;
    }

    fun void step(int x, int y) {
        countNeighbors(x, y) => int neighborcount;
        if(lifeState[x][y] == 1) {
            if(neighborcount == 2 || neighborcount == 3) {
                1 => nextLifeState[x][y];
            } else {
                0 => nextLifeState[x][y];
            }
        } else {
            if(neighborcount == 3) {
                1 => nextLifeState[x][y];
            } else {
                0 => nextLifeState[x][y];
            }
        }
    }

    fun int wrap(int x) {
        if(x > 7) return 0;
        if(x < 0) return 7;
        return x;
    }

    fun int countNeighbors(int x, int y) {
        0 => int count;
        wrap(x - 1) => int left_x;
        wrap(x + 1) => int right_x;
        wrap(y - 1) => int up_y;
        wrap(y + 1) => int down_y;

        lifeState[left_x][up_y] +=> count;
        lifeState[x][up_y] +=> count;
        lifeState[right_x][up_y] +=> count;
        lifeState[left_x][y] +=> count;
        lifeState[right_x][y] +=> count;
        lifeState[left_x][down_y] +=> count;
        lifeState[x][down_y] +=> count;
        lifeState[right_x][down_y] +=> count;

        return count;
    }

    fun void key(int x, int y, int z) {
        if(z == 0) {
            return;
        }
        toggle(x, y);
    }

    fun void toggle(int x, int y) {
        if(lifeState[x][y] == 0) {
            1 => lifeState[x][y];
        } else {
            0 => lifeState[x][y];
        }
        set(x, y, lifeState[x][y]);
    }
}

new Life @=> Life m;
m.init(monomePrefix, monomeHost, monomeIn, monomeOut);

fun void keyboardHandler() {
    Hid hi;
    HidMsg msg;
    if(!hi.openKeyboard(0)) {
        <<< "can't open keyboard" >>>;
        return;
    }
    while(true) {
        hi => now;
        while(hi.recv(msg)) {
            if(msg.isButtonDown()) {
                if(msg.which == 44) {
                    m.pause();
                }
            }
        }
    }
}

spork ~ keyboardHandler();

while(true) { 1::second => now; }
