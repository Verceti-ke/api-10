(in-package :tagit)

(defun make-invite-id (item-id to-email)
  "Create a deterministic id based off the item-id and email."
  (sha256 (concatenate 'string item-id ":" to-email)))

(defafun get-invite-by-id (future) (invite-id)
  "gibiLOLOL"
  (alet* ((sock (db-sock))
          (query (r:r (:get (:table "invites") invite-id)))
          (invite (r:run sock query)))
    (r:disconnect sock)
    (finish future invite)))

(defafun make-invite-code (future) (to-email &optional (salt (crypto-random)))
  "Creates a *unique* (as in, not used by other invites) invite code and returns
   it. Invite codes are meant to be random."
  (alet* ((hash (sha256 (format nil "~a:~a:~a:~a" salt (get-universal-time) (get-internal-real-time) to-email)))
          (code (subseq hash (- (length hash) 7)))
          (sock (db-sock))
          (query (r:r (:count
                        (:get-all (:table "invites")
                                  code
                                  :index "code"))))
          (num (r:run sock query)))
    (r:disconnect sock)
    ;; loop until we have a unique code
    (if (< 0 num)
        ;; this code is in use, generate a new one (async recurs)
        (alet ((code (make-invite-code to-email (1+ salt))))
          (finish future code))
        ;; code is not being used
        (finish future code))))

(defafun create-invite (future) (type item-id to-email invite-data expire)
  "Create an invite record which has the ability to attach a set of data to a
   new user's account on join."
  (alet ((invite (make-hash-table :test #'equal))
         (invite-id (make-invite-id item-id to-email))
         (code (make-invite-code to-email)))
    (setf (gethash "id" invite) invite-id
          (gethash "code" invite) code
          (gethash "type" invite) type
          (gethash "to" invite) to-email
          (gethash "item_id" invite) item-id
          (gethash "expire" invite) (+ (get-timestamp) expire)
          (gethash "data" invite) invite-data)
    (finish future invite)))

(defafun insert-invite-record (future) (invite)
  "Inserts an invite hash/object into the db."
  (alet* ((sock (db-sock))
          (query (r:r (:insert (:table "invites") invite)))
          (nil (r:run sock query)))
    (r:disconnect sock)
    (finish future t)))

(defafun create-board-invite (future) (user-id board-id persona-id challenge to-email key board-key used-secret-p)
  "Create (and send) a board invite. Also creates a stubbed persona for the
   invitee which is tied to them when they accept the invite."
  ;; make sure the persona/board auth check out
  (with-valid-persona (persona-id challenge future)
    (alet* ((exists-invite-id (make-invite-id board-id to-email))
            (exists-invite (get-invite-by-id exists-invite-id))
            (persona (get-persona-by-id persona-id)))
      (if exists-invite
          ;; this email/board-id invite already exists. just resend it
          (wait-for (email-board-invite persona exists-invite)
            (finish future exists-invite))
          ;; new invite, create/insert/send it
          (alet* ((expire (* 3 86400))
                  (invite-data (let ((hash (make-hash-table :test #'equal)))
                                 (setf (gethash "key" hash) key
                                       (gethash "board_key" hash) board-key
                                       (gethash "used_secret" hash) used-secret-p)
                                 hash))
                  (invite (create-invite "b" board-id to-email invite-data expire))
                  (invite-id (gethash "id" invite)))
            (multiple-future-bind (nil priv-entry)
                (add-board-remote-invite user-id board-id invite-id 2 to-email)
              (alet* ((nil (insert-invite-record invite))
                      (nil (email-board-invite persona invite)))
                (setf (gethash "priv" invite) (convert-alist-hash priv-entry))
                (finish future invite))))))))

(defafun delete-invite (future) (user-id invite-id)
  "Delete an invite."
  (alet* ((invite (get-invite-by-id invite-id))
          (invite-type (gethash "type" invite))
          (invite-type-keyword (intern (string-upcase invite-type) :keyword))
          (res (case invite-type-keyword
                 (:b (delete-board-invite user-id invite))))
          (sock (db-sock))
          (query (r:r (:delete (:get (:table "invites") invite-id))))
          (nil (r:run sock query)))
    (r:disconnect sock)
    (finish future res)))

(defafun delete-board-invite (future) (user-id invite)
  "Delete a board invite."
  (alet* ((invite-id (gethash "id" invite))
          (board-id (gethash "item_id" invite))
          (perm (set-board-persona-permissions user-id board-id invite-id 0)))
    (finish future perm)))

(defafun cleanup-invites (future) ()
  "Delete expired invites."
  (alet* ((sock (db-sock))
          (query (r:r
                   (:delete
                     (:filter
                       (:table "invites")
                       (r:fn (c)
                         (:< (:attr c "expire") (get-timestamp)))))))
          (nil (r:run sock query)))
    (r:disconnect sock)
    (finish future t)))
