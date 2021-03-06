/**
 * Copyright 2004-present Facebook. All Rights Reserved.
 *
 * @providesModule FeedUFI.react
 * @flow
 */

'use strict';

var UFILikeCount = require('UFILikeCount.react');
var React = require('react');

var FeedUFI = React.createClass({
  _renderLikeCount: function(
      feedback: any
  ): ReactElement {
    var props = {
      className: "",
      key: "",
      feedback: {feedback},
      permalink: "",
    };
    var ignored = <UFILikeCount {...props} />;
    return (
      <UFILikeCount
        className=""
        key=""
        feedback={feedback}
        permalink=""
      />
    );
  },

  render: function(): ?ReactElement<any, any, any> {
    return (
      <div/>
    );
  }

});

module.exports = FeedUFI;
